import dataclasses
import time

from fastapi.testclient import TestClient

from services.api.main import create_app


def _client(settings):
    return TestClient(create_app(settings, startup_retry_base_s=0.01))


def _wait_until(client, predicate, timeout_s=10):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        body = client.get("/readyz").json()
        if predicate(body):
            return body
        time.sleep(0.02)
    raise AssertionError(f"condition not met, last /readyz: {body}")


def _ready(body):
    return body["status"] == "ready"


def test_recommend_happy_path(settings):
    with _client(settings) as client:
        assert client.get("/healthz").status_code == 200
        _wait_until(client, _ready)
        assert client.get("/readyz").status_code == 200
        resp = client.post("/recommend", json={"query": "light hearted school anime"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["model"] == "fake"
        assert len(body["retrieved_titles"]) == settings.retriever_k
        assert "Fake Anime A" in body["recommendations"]


def test_validation(settings):
    with _client(settings) as client:
        _wait_until(client, _ready)
        assert client.post("/recommend", json={"query": ""}).status_code == 422
        assert client.post("/recommend", json={"query": "x" * 501}).status_code == 422


def test_upstream_failure_maps_to_503(settings):
    with _client(dataclasses.replace(settings, fault_rate=1.0)) as client:
        _wait_until(client, _ready)
        resp = client.post("/recommend", json={"query": "mecha"})
        assert resp.status_code == 503
        assert resp.headers["retry-after"] == "2"


def test_not_ready_when_index_count_mismatches(settings):
    with _client(dataclasses.replace(settings, expected_docs=270)) as client:
        _wait_until(client, lambda body: body.get("error"))
        ready = client.get("/readyz")
        assert ready.status_code == 503
        assert "expected 270" in ready.json()["error"]
        assert client.post("/recommend", json={"query": "mecha"}).status_code == 503
        assert client.get("/healthz").status_code == 200


def test_transient_startup_failure_is_retried(settings, monkeypatch):
    import services.api.main as api_main

    real_load = api_main.load_state
    attempts = []

    def flaky_load(s, state):
        attempts.append(1)
        if len(attempts) == 1:
            raise ConnectionError("Temporary failure in name resolution")
        real_load(s, state)

    monkeypatch.setattr(api_main, "load_state", flaky_load)
    with _client(settings) as client:
        _wait_until(client, _ready)
        assert len(attempts) == 2


def test_metrics_exported(settings):
    with _client(settings) as client:
        _wait_until(client, _ready)
        client.post("/recommend", json={"query": "romance"})
        client.post("/recommend", json={"query": ""})
        text = client.get("/metrics").text
    for name in (
        'anime_http_requests_total{method="POST",route="/recommend",status="200"}',
        'anime_http_requests_total{method="POST",route="/recommend",status="422"}',
        "anime_http_request_duration_seconds_bucket",
        "anime_http_requests_in_flight",
        "anime_retrieval_duration_seconds_bucket",
        'anime_llm_request_duration_seconds_bucket{le="0.1",model="fake",outcome="ok"}',
        'anime_llm_tokens_total{model="fake",type="output"}',
        'anime_llm_cost_usd_total{model="fake"}',
        "anime_index_info",
    ):
        assert name in text, name
    assert 'route="/metrics"' not in text
