import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.vectorstores import VectorStore
from opentelemetry.trace import SpanKind

from anime.providers import UpstreamError
from anime.telemetry import capture_content, tracer

# The GenAI semantic conventions' provider names; they are still in development, so this is checked against the
# version in use (design §4.2). The fake provider is named plainly, so a trace can never pass for a real model's.
PROVIDER_NAMES = {"gemini": "gcp.gemini", "fake": "fake"}


@dataclass
class Recommendation:
    text: str
    model: str
    retrieval_s: float
    llm_s: float
    titles: list[str] = field(default_factory=list)
    usage: dict = field(default_factory=dict)


def load_prompt(path: Path) -> PromptTemplate:
    return PromptTemplate(template=path.read_text(encoding="utf-8"), input_variables=["context", "question"])


class Recommender:
    """Retrieve top-k anime, then ask the LLM for 3 explained picks. Each step gets its own span and timing."""

    def __init__(self, vectorstore: VectorStore, llm, prompt: PromptTemplate, k: int, model_name: str,
                 provider: str = "gemini"):
        self.vectorstore, self.llm, self.prompt = vectorstore, llm, prompt
        self.k, self.model_name, self.provider = k, model_name, provider

    def recommend(self, query: str) -> Recommendation:
        t = tracer()
        with t.start_as_current_span("rag.retrieve") as span:
            t0 = time.perf_counter()
            # The search embeds the query through the embedding API. Its failure used to escape as an unhandled 500,
            # with no Retry-After and nothing in any error metric; it is an upstream failure like the model's. The
            # catch is deliberately broad: a local fault in the index lands here too, so the 503 says "retrieval",
            # not "embedding", and the stage label is where to start, not a diagnosis.
            try:
                docs = self.vectorstore.similarity_search(query, k=self.k)
            except Exception as exc:
                raise UpstreamError(f"{type(exc).__name__}: {exc}", stage="retrieval") from exc
            retrieval_s = time.perf_counter() - t0
            span.set_attribute("rag.top_k", self.k)
            span.set_attribute("rag.docs_returned", len(docs))

        # CLIENT, not the default INTERNAL: this span is a call out to a remote model, which is what the conventions
        # (and Langfuse's reading of them) expect for a generation.
        with t.start_as_current_span(f"chat {self.model_name}", kind=SpanKind.CLIENT) as span:
            span.set_attribute("gen_ai.operation.name", "chat")
            span.set_attribute("gen_ai.provider.name", PROVIDER_NAMES.get(self.provider, self.provider))
            span.set_attribute("gen_ai.request.model", self.model_name)
            prompt_value = self.prompt.invoke(
                {"context": "\n\n".join(d.page_content for d in docs), "question": query}
            )
            t1 = time.perf_counter()
            try:
                message = self.llm.invoke(prompt_value)
            except UpstreamError:
                raise
            except Exception as exc:
                raise UpstreamError(f"{type(exc).__name__}: {exc}") from exc
            llm_s = time.perf_counter() - t1
            usage = dict(getattr(message, "usage_metadata", None) or {})
            # Set only when the provider reported them. A default of 0 made "the trace carries token counts" true while
            # token capture was broken; a missing attribute is visibly missing (design §6, row 11).
            for key in ("input_tokens", "output_tokens"):
                if key in usage:
                    span.set_attribute(f"gen_ai.usage.{key}", usage[key])
            if capture_content():
                # The conventions' message attributes, and Langfuse's own names for the same, so the text shows as
                # the generation's input and output whichever mapping the Langfuse version applies (to be verified).
                prompt_text = prompt_value.to_string()
                completion_text = StrOutputParser().invoke(message)
                span.set_attribute("gen_ai.input.messages", json.dumps(
                    [{"role": "user", "parts": [{"type": "text", "content": prompt_text}]}]))
                span.set_attribute("gen_ai.output.messages", json.dumps(
                    [{"role": "assistant", "parts": [{"type": "text", "content": completion_text}]}]))
                span.set_attribute("langfuse.observation.input", prompt_text)
                span.set_attribute("langfuse.observation.output", completion_text)

        return Recommendation(
            text=StrOutputParser().invoke(message),
            model=self.model_name,
            retrieval_s=retrieval_s,
            llm_s=llm_s,
            titles=[d.metadata.get("title", "") for d in docs],
            usage=usage,
        )
