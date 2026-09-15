import time
from dataclasses import dataclass, field
from pathlib import Path

from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.vectorstores import VectorStore

from anime.providers import UpstreamError
from anime.telemetry import tracer


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

    def __init__(self, vectorstore: VectorStore, llm, prompt: PromptTemplate, k: int, model_name: str):
        self.vectorstore, self.llm, self.prompt = vectorstore, llm, prompt
        self.k, self.model_name = k, model_name

    def recommend(self, query: str) -> Recommendation:
        t = tracer()
        with t.start_as_current_span("rag.retrieve") as span:
            t0 = time.perf_counter()
            docs = self.vectorstore.similarity_search(query, k=self.k)
            retrieval_s = time.perf_counter() - t0
            span.set_attribute("rag.top_k", self.k)
            span.set_attribute("rag.docs_returned", len(docs))

        with t.start_as_current_span(f"chat {self.model_name}") as span:
            span.set_attribute("gen_ai.operation.name", "chat")
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
            span.set_attribute("gen_ai.usage.input_tokens", usage.get("input_tokens", 0))
            span.set_attribute("gen_ai.usage.output_tokens", usage.get("output_tokens", 0))

        return Recommendation(
            text=StrOutputParser().invoke(message),
            model=self.model_name,
            retrieval_s=retrieval_s,
            llm_s=llm_s,
            titles=[d.metadata.get("title", "") for d in docs],
            usage=usage,
        )
