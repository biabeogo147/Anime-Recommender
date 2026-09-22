import os
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _env(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value not in (None, "") else default


# The model each real provider runs when MODEL_NAME is not set; the cluster sets it from the chart's own map.
DEFAULT_MODELS = {"gemini": "gemini-3.5-flash-lite", "openai": "gpt-4o-mini"}


@dataclass(frozen=True)
class Settings:
    llm_provider: str
    model_name: str
    embedding_model_name: str
    google_api_key: str | None
    openai_api_key: str | None
    hf_token: str | None
    retriever_k: int
    llm_timeout_s: float
    fake_latency_ms: float
    fault_rate: float
    index_dir: Path
    expected_docs: int
    data_csv: Path
    prompt_path: Path
    pricing_path: Path
    log_level: str

    @property
    def fake(self) -> bool:
        return self.llm_provider == "fake"


def get_settings() -> Settings:
    provider = _env("LLM_PROVIDER", "gemini")
    return Settings(
        llm_provider=provider,
        model_name=_env("MODEL_NAME", DEFAULT_MODELS.get(provider, DEFAULT_MODELS["gemini"])),
        embedding_model_name=_env("EMBEDDING_MODEL_NAME", "sentence-transformers/all-MiniLM-L6-v2"),
        google_api_key=os.getenv("GOOGLE_API_KEY"),
        openai_api_key=os.getenv("OPENAI_API_KEY"),
        hf_token=os.getenv("HF_TOKEN") or os.getenv("HUGGINGFACEHUB_API_TOKEN"),
        retriever_k=int(_env("RETRIEVER_K", "4")),
        llm_timeout_s=float(_env("LLM_TIMEOUT_S", "30")),
        fake_latency_ms=float(_env("FAKE_LATENCY_MS", "800")),
        fault_rate=float(_env("FAULT_RATE", "0")),
        index_dir=Path(_env("INDEX_DIR", str(PROJECT_ROOT / "index"))),
        expected_docs=int(_env("EXPECTED_DOCS", "269")),
        data_csv=Path(_env("DATA_CSV", str(PROJECT_ROOT / "data" / "anime_with_synopsis.csv"))),
        prompt_path=Path(_env("PROMPT_PATH", str(PROJECT_ROOT / "data" / "prompt_template.txt"))),
        pricing_path=Path(_env("PRICING_PATH", str(PROJECT_ROOT / "config" / "pricing.yaml"))),
        log_level=_env("LOG_LEVEL", "INFO"),
    )
