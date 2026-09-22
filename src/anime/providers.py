"""Model providers. `fake` exists for load tests and failure drills: no network, controllable latency and errors."""

import hashlib
import json
import logging
import random
import time
import urllib.error
import urllib.request
from collections.abc import Callable

import numpy as np
from langchain_core.embeddings import Embeddings
from langchain_core.messages import AIMessage

from anime.config import Settings

logger = logging.getLogger(__name__)

EMBEDDING_DIM = 384
RETRYABLE_STATUS = {408, 429, 500, 502, 503, 504}


class UpstreamError(RuntimeError):
    """A remote dependency failed; the API maps this to 503 with Retry-After.

    `stage` says which one: "llm" for the model call, "retrieval" for the embedding call made to search the index.
    """

    def __init__(self, message: str, stage: str = "llm"):
        super().__init__(message)
        self.stage = stage


def _status_code(exc: Exception) -> int | None:
    return getattr(getattr(exc, "response", None), "status_code", None)


def is_retryable(exc: Exception) -> bool:
    status = _status_code(exc)
    if status is None:
        return isinstance(exc, (ConnectionError, TimeoutError, OSError)) or "Timeout" in type(exc).__name__
    return status in RETRYABLE_STATUS


class BatchedEmbeddings(Embeddings):
    """Batches documents and retries transient API errors with exponential backoff."""

    def __init__(self, inner: Embeddings, batch_size: int = 64, max_attempts: int = 6,
                 base_delay_s: float = 1.0, sleep: Callable[[float], None] = time.sleep):
        self.inner, self.batch_size, self.max_attempts = inner, batch_size, max_attempts
        self.base_delay_s, self.sleep = base_delay_s, sleep

    def _with_retry(self, fn, arg):
        for attempt in range(1, self.max_attempts + 1):
            try:
                return fn(arg)
            except Exception as exc:
                if attempt == self.max_attempts or not is_retryable(exc):
                    raise
                delay = self.base_delay_s * 2 ** (attempt - 1) * (1 + random.random() * 0.25)
                logger.warning("Embedding call failed (attempt %d, status=%s); retry in %.1fs",
                               attempt, _status_code(exc), delay)
                self.sleep(delay)

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        out: list[list[float]] = []
        for start in range(0, len(texts), self.batch_size):
            out.extend(self._with_retry(self.inner.embed_documents, texts[start:start + self.batch_size]))
        return out

    def embed_query(self, text: str) -> list[float]:
        return self._with_retry(self.inner.embed_query, text)


class HashEmbeddings(Embeddings):
    """Deterministic pseudo-embeddings: same text -> same unit vector, no network."""

    def _vector(self, text: str) -> list[float]:
        seed = int.from_bytes(hashlib.sha256(text.encode()).digest()[:8], "big")
        vec = np.random.default_rng(seed).standard_normal(EMBEDDING_DIM)
        return (vec / np.linalg.norm(vec)).tolist()

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._vector(t) for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._vector(text)


class FakeLLM:
    """Stands in for the chat model: lognormal latency around the median, random faults, synthetic usage."""

    def __init__(self, median_latency_ms: float, fault_rate: float, rng: random.Random | None = None,
                 sleep: Callable[[float], None] = time.sleep):
        self.median_latency_ms, self.fault_rate = median_latency_ms, fault_rate
        self.rng = rng or random.Random()
        self.sleep = sleep

    def invoke(self, prompt_value) -> AIMessage:
        self.sleep(self.median_latency_ms / 1000 * self.rng.lognormvariate(0, 0.35))
        if self.rng.random() < self.fault_rate:
            raise UpstreamError("fake provider injected fault")
        prompt_tokens = max(1, len(str(prompt_value)) // 4)
        return AIMessage(
            content="1. Fake Anime A - placeholder.\n2. Fake Anime B - placeholder.\n3. Fake Anime C - placeholder.",
            usage_metadata={"input_tokens": prompt_tokens, "output_tokens": 60, "total_tokens": prompt_tokens + 60},
        )


class OpenAIChat:
    """OpenAI's Chat Completions API (gpt-4o-mini by default in the cluster), called with the standard library.

    No SDK and no LangChain integration: either would be a new dependency and a regenerated uv.lock, for one POST.
    It answers like FakeLLM and the Gemini client do — an AIMessage whose usage_metadata the recommender turns into
    token attributes and the cost metric reads — so nothing downstream knows which provider answered.

    Added on 2026-09-22, when gemini-3.5-flash-lite took about 50 s per call from the ops workstation and every call
    through the api hit its 30 s timeout; gpt-4o-mini answered in 1–3 s from the same place (design §4.1).
    """

    URL = "https://api.openai.com/v1/chat/completions"

    def __init__(self, model: str, api_key: str, timeout_s: float, url: str = URL,
                 opener: Callable = urllib.request.urlopen):
        self.model, self.api_key, self.timeout_s, self.url, self.opener = model, api_key, timeout_s, url, opener

    def invoke(self, prompt_value) -> AIMessage:
        text = prompt_value.to_string() if hasattr(prompt_value, "to_string") else str(prompt_value)
        request = urllib.request.Request(
            self.url,
            data=json.dumps({"model": self.model, "messages": [{"role": "user", "content": text}]}).encode(),
            headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
        )
        # No retry. T is the latency of one call, and a retry hidden in here would fold a failure's wait into a success;
        # a failed call is an UpstreamError, a 503 the client can retry, and a count in the LLM error metric.
        try:
            with self.opener(request, timeout=self.timeout_s) as response:
                body = json.load(response)
            content = body["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as exc:
            # The message ends up in the log line and on the span as an exception event. For 401/403 OpenAI's text
            # echoes a masked form of the key ("sk-proj-****abcd"), so it is replaced; for everything else (a rate
            # limit, an overload) OpenAI's own text says what was wrong. The request, which holds the key, is never
            # put into the message.
            detail = "authentication failed"
            if exc.code not in (401, 403):
                try:
                    detail = json.load(exc).get("error", {}).get("message", "")
                except (ValueError, AttributeError, OSError):
                    detail = ""
            raise UpstreamError(f"OpenAI HTTP {exc.code}: {detail}".strip()) from None
        except OSError as exc:  # URLError, a connect or read timeout (TimeoutError), a reset connection
            raise UpstreamError(f"OpenAI unreachable: {type(exc).__name__}") from None
        except (ValueError, KeyError, IndexError, TypeError) as exc:  # a 200 whose body is not the expected shape
            raise UpstreamError(f"OpenAI bad response: {type(exc).__name__}") from None
        if content is None:  # a refusal carries no text
            raise UpstreamError("OpenAI returned no content")

        usage = body.get("usage") or {}
        # Set only when the API reported usage, the rule the recommender's token attributes follow (design §6, row 11).
        usage_metadata = None
        if "prompt_tokens" in usage and "completion_tokens" in usage:
            usage_metadata = {
                "input_tokens": usage["prompt_tokens"],
                "output_tokens": usage["completion_tokens"],
                "total_tokens": usage.get("total_tokens", usage["prompt_tokens"] + usage["completion_tokens"]),
            }
        return AIMessage(content=content, usage_metadata=usage_metadata)


def get_embeddings(settings: Settings, provider: str | None = None) -> Embeddings:
    provider = provider or ("fake" if settings.fake else "hf")
    if provider == "fake":
        return HashEmbeddings()
    if provider != "hf":
        raise ValueError(f"Unknown embeddings provider: {provider}")
    if not settings.hf_token:
        raise RuntimeError("HF_TOKEN is not set")
    from langchain_huggingface import HuggingFaceEndpointEmbeddings

    return BatchedEmbeddings(
        HuggingFaceEndpointEmbeddings(repo_id=settings.embedding_model_name, huggingfacehub_api_token=settings.hf_token)
    )


def get_llm(settings: Settings):
    if settings.fake:
        return FakeLLM(settings.fake_latency_ms, settings.fault_rate)
    if settings.llm_provider == "openai":
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is not set")
        return OpenAIChat(settings.model_name, settings.openai_api_key, settings.llm_timeout_s)
    if settings.llm_provider != "gemini":
        raise ValueError(f"Unknown LLM provider: {settings.llm_provider}")
    if not settings.google_api_key:
        raise RuntimeError("GOOGLE_API_KEY is not set")
    from langchain_google_genai import ChatGoogleGenerativeAI

    return ChatGoogleGenerativeAI(
        model=settings.model_name, google_api_key=settings.google_api_key,
        timeout=settings.llm_timeout_s, max_retries=1,
    )
