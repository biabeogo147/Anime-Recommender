from prometheus_client import Counter, Gauge, Histogram, Info

# Dense between 0.75 s and 3 s, where both the fake provider's p95 (~1.4 s) and a plausible T fall. With the old
# (0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32) a canary gate written as 1.2x actually tripped at ~1.43x, and T could only be
# 2, 4 or 8 s; with these the gate trips near 1.22x and T can be 2.5 or 3 (design §4.1, computed, not measured).
# T must be one of these boundaries — the SLI asks for the counter at le=T, which exists only here.
LATENCY_BUCKETS = (0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 6, 8, 16, 32)

HTTP_REQUESTS = Counter("anime_http_requests_total", "HTTP requests", ["route", "method", "status"])
HTTP_LATENCY = Histogram(
    "anime_http_request_duration_seconds", "HTTP request latency", ["route"], buckets=LATENCY_BUCKETS
)
HTTP_IN_FLIGHT = Gauge("anime_http_requests_in_flight", "Requests currently being served")
RETRIEVAL_LATENCY = Histogram(
    "anime_retrieval_duration_seconds", "Vector retrieval latency", buckets=LATENCY_BUCKETS
)
LLM_LATENCY = Histogram(
    "anime_llm_request_duration_seconds", "LLM call latency", ["model", "outcome"], buckets=LATENCY_BUCKETS
)
LLM_TOKENS = Counter("anime_llm_tokens_total", "LLM tokens", ["model", "type"])
LLM_COST = Counter("anime_llm_cost_usd_total", "Estimated LLM cost in USD", ["model"])
INDEX_INFO = Info("anime_index", "Loaded vector index")
# Failures of a remote dependency, by where they happened: the embedding call during retrieval, or the model call.
UPSTREAM_ERRORS = Counter("anime_upstream_errors_total", "Upstream dependency failures", ["stage"])
# Created at zero, so a rate over them is 0 before the first failure rather than an empty answer.
for _stage in ("llm", "retrieval"):
    UPSTREAM_ERRORS.labels(_stage)
