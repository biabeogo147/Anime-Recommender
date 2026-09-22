"""OpenTelemetry tracing, enabled only when OTEL_EXPORTER_OTLP_ENDPOINT is set."""

import logging
import os

from opentelemetry import trace

logger = logging.getLogger(__name__)


def setup_tracing(app, service_name: str = "anime-api") -> bool:
    if not os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return False
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    # Resource.create also reads OTEL_RESOURCE_ATTRIBUTES. The chart sets anime.llm.provider there, from the same value
    # as LLM_PROVIDER, so every span this pod emits says which provider served it — the collector's Langfuse pipeline
    # keeps only real providers by that attribute (design §4.2).
    provider = TracerProvider(resource=Resource.create({"service.name": service_name}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz,metrics")
    logger.info("OpenTelemetry tracing enabled")
    return True


def capture_content() -> bool:
    """Whether spans carry the prompt and the completion. Off unless OTEL_CAPTURE_CONTENT is true: a user's free text is
    copied to whatever the traces are exported to. This deployment turns it on for a single-operator demonstration
    (design §4.2); a regulated context would leave it off."""
    return os.getenv("OTEL_CAPTURE_CONTENT", "false").strip().lower() in ("1", "true", "yes")


def tracer():
    return trace.get_tracer("anime")


def current_trace_id() -> str | None:
    ctx = trace.get_current_span().get_span_context()
    return format(ctx.trace_id, "032x") if ctx.is_valid else None
