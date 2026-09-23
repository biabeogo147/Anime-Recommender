import dataclasses
import io
import json
import random
import urllib.error

import pytest
from langchain_core.embeddings import Embeddings

from anime.pricing import Pricing
from anime.providers import (
    BatchedEmbeddings,
    FakeLLM,
    HashEmbeddings,
    OpenAIChat,
    UpstreamError,
    get_embeddings,
    get_llm,
)

KEY = "sk-test-not-a-real-key"


def test_fake_provider_selection(settings):
    assert isinstance(get_embeddings(settings), HashEmbeddings)
    assert isinstance(get_llm(settings), FakeLLM)


def test_real_provider_requires_keys(settings):
    real = dataclasses.replace(settings, llm_provider="gemini", google_api_key=None, hf_token=None)
    with pytest.raises(RuntimeError, match="GOOGLE_API_KEY"):
        get_llm(real)
    with pytest.raises(RuntimeError, match="HF_TOKEN"):
        get_embeddings(real)


def test_openai_provider_selection_and_key(settings):
    real = dataclasses.replace(settings, llm_provider="openai", model_name="gpt-4o-mini", openai_api_key=None)
    with pytest.raises(RuntimeError, match="OPENAI_API_KEY"):
        get_llm(real)
    llm = get_llm(dataclasses.replace(real, openai_api_key=KEY))
    assert isinstance(llm, OpenAIChat) and llm.model == "gpt-4o-mini"


def test_openai_parses_answer_and_usage():
    seen = {}

    def opener(request, timeout):
        seen["body"], seen["timeout"] = json.loads(request.data), timeout
        seen["auth"] = request.get_header("Authorization")
        return io.BytesIO(json.dumps({
            "choices": [{"message": {"role": "assistant", "content": "1. Shokugeki no Soma"}}],
            "usage": {"prompt_tokens": 812, "completion_tokens": 95, "total_tokens": 907},
        }).encode())

    message = OpenAIChat("gpt-4o-mini", KEY, 30, opener=opener).invoke("prompt text")
    assert message.content == "1. Shokugeki no Soma"
    assert message.usage_metadata == {"input_tokens": 812, "output_tokens": 95, "total_tokens": 907}
    assert seen["body"] == {"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "prompt text"}]}
    assert seen["auth"] == f"Bearer {KEY}" and seen["timeout"] == 30


def test_openai_missing_usage_is_absent_not_zero():
    def opener(request, timeout):
        return io.BytesIO(json.dumps({"choices": [{"message": {"content": "ok"}}]}).encode())

    assert not OpenAIChat("gpt-4o-mini", KEY, 30, opener=opener).invoke("p").usage_metadata


def test_openai_auth_error_is_upstream_and_drops_the_masked_key():
    def opener(request, timeout):
        body = io.BytesIO(json.dumps({"error": {"message": "Incorrect API key provided: sk-test-****-key"}}).encode())
        raise urllib.error.HTTPError(request.full_url, 401, "Unauthorized", {}, body)

    with pytest.raises(UpstreamError) as info:
        OpenAIChat("gpt-4o-mini", KEY, 30, opener=opener).invoke("p")
    assert str(info.value) == "OpenAI HTTP 401: authentication failed" and info.value.stage == "llm"


def test_openai_rate_limit_keeps_the_providers_reason():
    def opener(request, timeout):
        body = io.BytesIO(json.dumps({"error": {"message": "Rate limit reached"}}).encode())
        raise urllib.error.HTTPError(request.full_url, 429, "Too Many Requests", {}, body)

    with pytest.raises(UpstreamError, match="429: Rate limit reached"):
        OpenAIChat("gpt-4o-mini", KEY, 30, opener=opener).invoke("p")


@pytest.mark.parametrize("failure", [TimeoutError("read timed out"), b"not json", b'{"choices": []}',
                                     b'{"choices": [{"message": {"content": null}}]}'])
def test_openai_timeouts_and_bad_answers_are_upstream_errors(failure):
    def opener(request, timeout):
        if isinstance(failure, Exception):
            raise failure
        return io.BytesIO(failure)

    with pytest.raises(UpstreamError):
        OpenAIChat("gpt-4o-mini", KEY, 30, opener=opener).invoke("p")


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
