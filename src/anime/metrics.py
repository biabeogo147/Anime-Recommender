from prometheus_client import Counter, Gauge, Histogram, Info

LATENCY_BUCKETS = (0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32)

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
