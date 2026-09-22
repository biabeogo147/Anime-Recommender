import dataclasses
import random

import pytest
from langchain_core.embeddings import Embeddings

from anime.pricing import Pricing
from anime.providers import (
    BatchedEmbeddings,
    FakeLLM,
    HashEmbeddings,
    UpstreamError,
    get_embeddings,
    get_llm,
)


def test_fake_provider_selection(settings):
    assert isinstance(get_embeddings(settings), HashEmbeddings)
    assert isinstance(get_llm(settings), FakeLLM)


def test_real_provider_requires_keys(settings):
    real = dataclasses.replace(settings, llm_provider="gemini", google_api_key=None, hf_token=None)
    with pytest.raises(RuntimeError, match="GOOGLE_API_KEY"):
        get_llm(real)
    with pytest.raises(RuntimeError, match="HF_TOKEN"):
        get_embeddings(real)


def test_hash_embeddings_deterministic_unit_vectors():
    emb = HashEmbeddings()
    a, b = emb.embed_query("naruto"), emb.embed_query("naruto")
    assert a == b and len(a) == 384
    assert abs(sum(x * x for x in a) - 1.0) < 1e-9
    assert emb.embed_query("one piece") != a


def test_fake_llm_fault_rate_is_honoured():
    llm = FakeLLM(median_latency_ms=0, fault_rate=0.2, rng=random.Random(42), sleep=lambda _: None)
    failures = 0
    for _ in range(2000):
        try:
            message = llm.invoke("prompt")
            assert message.usage_metadata["output_tokens"] == 60
        except UpstreamError:
            failures += 1
    assert 0.17 < failures / 2000 < 0.23


class Http429(Exception):
    response = type("Resp", (), {"status_code": 429})()


class Flaky(Embeddings):
    def __init__(self):
        self.calls = 0

    def embed_documents(self, texts):
        self.calls += 1
        if self.calls == 1:
            raise Http429()
        return [[0.0] for _ in texts]

    def embed_query(self, text):
        return [0.0]


def test_batched_embeddings_retries_rate_limits():
    inner = Flaky()
    embeddings = BatchedEmbeddings(inner, batch_size=2, sleep=lambda _: None)
    assert len(embeddings.embed_documents(["a", "b", "c"])) == 3
    assert inner.calls == 3  # 1 failure + 2 batches


def test_pricing(tmp_path):
    path = tmp_path / "pricing.yaml"
    path.write_text("models:\n  m:\n    input_per_1m: 0.30\n    output_per_1m: 2.50\n")
    pricing = Pricing.load(path)
    assert pricing.cost_usd("m", 1_000_000, 0) == pytest.approx(0.30)
    assert pricing.cost_usd("m", 2000, 400) == pytest.approx((2000 * 0.30 + 400 * 2.50) / 1e6)
    assert pricing.cost_usd("unknown", 1000, 1000) == 0.0
