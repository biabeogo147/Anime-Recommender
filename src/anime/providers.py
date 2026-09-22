"""Model providers. `fake` exists for load tests and failure drills: no network, controllable latency and errors."""

import hashlib
import logging
import random
import time
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
    if settings.llm_provider != "gemini":
        raise ValueError(f"Unknown LLM provider: {settings.llm_provider}")
    if not settings.google_api_key:
        raise RuntimeError("GOOGLE_API_KEY is not set")
    from langchain_google_genai import ChatGoogleGenerativeAI

    return ChatGoogleGenerativeAI(
        model=settings.model_name, google_api_key=settings.google_api_key,
        timeout=settings.llm_timeout_s, max_retries=1,
    )
