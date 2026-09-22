import dataclasses
import os

import pytest

os.environ["ANONYMIZED_TELEMETRY"] = "False"
os.environ.pop("OTEL_EXPORTER_OTLP_ENDPOINT", None)

from anime.config import get_settings  # noqa: E402
from anime.index import build_index  # noqa: E402
from anime.providers import HashEmbeddings  # noqa: E402


@pytest.fixture(scope="session")
def fake_index(tmp_path_factory):
    out = tmp_path_factory.mktemp("index") / "chroma"
    settings = dataclasses.replace(get_settings(), llm_provider="fake")
    build_index(settings, out, HashEmbeddings(), "fake")
    return out


@pytest.fixture
def settings(fake_index):
    return dataclasses.replace(
        get_settings(), llm_provider="fake", fake_latency_ms=1, fault_rate=0.0, index_dir=fake_index
    )
