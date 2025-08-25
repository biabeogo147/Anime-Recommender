from prometheus_client import Counter, Histogram, Gauge, Info

REQUESTS = Counter("llmops_requests_total", "Total recommend requests")
LATENCY = Histogram(
    "llmops_request_latency_seconds",
    "Latency for recommend() in seconds",
    buckets=(0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10),
)
LATENCY.labels()
EXCEPTIONS = Counter("llmops_exceptions_total", "Total exceptions in recommend()")
APP_INFO = Info("llmops_app_info", "App build/info")
UP = Gauge("llmops_up", "App is up")