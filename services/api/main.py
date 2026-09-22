import asyncio
import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.concurrency import run_in_threadpool
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from anime import metrics
from anime.config import Settings, get_settings
from anime.index import open_index
from anime.log import configure_logging
from anime.pricing import Pricing
from anime.providers import UpstreamError, get_embeddings, get_llm
from anime.recommender import Recommender, load_prompt
from anime.telemetry import current_trace_id, setup_tracing

logger = logging.getLogger(__name__)

UNINSTRUMENTED_ROUTES = {"/metrics"}


class RecommendRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)


class RecommendResponse(BaseModel):
    recommendations: str
    model: str
    retrieved_titles: list[str]
    trace_id: str | None = None


class AppState:
    def __init__(self):
        self.recommender: Recommender | None = None
        self.pricing: Pricing | None = None
        self.error: str | None = None


def load_state(settings: Settings, state: AppState) -> None:
    embeddings = get_embeddings(settings)
    db, manifest = open_index(settings.index_dir, embeddings)
    count = db._collection.count()
    dim = len(embeddings.embed_query("dimension probe"))
    if count != settings.expected_docs:
        raise RuntimeError(f"Index holds {count} documents, expected {settings.expected_docs}")
    if dim != manifest["dim"]:
        raise RuntimeError(f"Query embedding dim {dim} != index dim {manifest['dim']}")
    model_name = "fake" if settings.fake else settings.model_name
    state.recommender = Recommender(db, get_llm(settings), load_prompt(settings.prompt_path),
                                    settings.retriever_k, model_name)
    state.pricing = Pricing.load(settings.pricing_path)
    metrics.INDEX_INFO.info({k: str(manifest[k]) for k in ("content_hash", "count", "embedding_model")})
    logger.info("Recommender ready: provider=%s model=%s docs=%d", settings.llm_provider, model_name, count)


def create_app(
    settings: Settings | None = None, startup_retry_base_s: float = 1.0, startup_retry_max_s: float = 30.0
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    state = AppState()

    async def load_until_ready():
        # A transient failure at boot (DNS, HF API) must not leave the pod permanently unready;
        # keep retrying and let the startup probe decide when to give up.
        delay = startup_retry_base_s
        attempt = 0
        while state.recommender is None:
            attempt += 1
            try:
                await run_in_threadpool(load_state, settings, state)
                state.error = None
            except Exception as exc:
                state.error = f"{type(exc).__name__}: {exc}"
                logger.warning("Startup attempt %d failed (%s); retrying in %.1fs", attempt, state.error, delay)
                await asyncio.sleep(delay)
                delay = min(delay * 2, startup_retry_max_s)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        loader = asyncio.create_task(load_until_ready())
        yield
        loader.cancel()

    app = FastAPI(title="Anime Recommender API", version="0.2.0", lifespan=lifespan)
    app.state.anime = state
    setup_tracing(app)

    @app.middleware("http")
    async def record_metrics(request: Request, call_next):
        path = request.url.path
        if path in UNINSTRUMENTED_ROUTES:
            return await call_next(request)
        metrics.HTTP_IN_FLIGHT.inc()
        started = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            metrics.HTTP_IN_FLIGHT.dec()
            route = request.scope.get("route")
            route_path = getattr(route, "path", "unmatched")
            metrics.HTTP_REQUESTS.labels(route_path, request.method, str(status)).inc()
            metrics.HTTP_LATENCY.labels(route_path).observe(time.perf_counter() - started)

    # The three endpoints below are `async def` on purpose. A plain `def` handler runs in the same bounded thread pool as
    # /recommend's model calls, so at saturation a probe or a scrape would queue behind forty busy threads, time out, and
    # mark a busy pod unready — or make the in-flight series vanish just when the autoscaler needs it (design §4.1).
    # None of them blocks, so they run on the event loop, independent of the pool.
    @app.get("/healthz")
    async def healthz():
        return {"status": "ok"}

    @app.get("/readyz")
    async def readyz(response: Response):
        if state.recommender is None:
            response.status_code = 503
            return {"status": "not ready", "error": state.error}
        return {"status": "ready"}

    @app.get("/metrics")
    async def prometheus_metrics():
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.post("/recommend", response_model=RecommendResponse)
    async def recommend(body: RecommendRequest):
        recommender = state.recommender
        if recommender is None:
            raise HTTPException(status_code=503, detail="Recommender not ready", headers={"Retry-After": "5"})
        started = time.perf_counter()
        try:
            result = await run_in_threadpool(recommender.recommend, body.query)
        except UpstreamError as exc:
            metrics.UPSTREAM_ERRORS.labels(exc.stage).inc()
            if exc.stage == "llm":
                # Timed from before the thread pool: an error's latency includes queueing and retrieval, so under
                # saturation it is longer than the model call itself. The "ok" series is the model call alone.
                metrics.LLM_LATENCY.labels(recommender.model_name, "error").observe(time.perf_counter() - started)
            logger.warning("Upstream failure (%s): %s", exc.stage, exc)
            detail = "Upstream model unavailable" if exc.stage == "llm" else "Retrieval unavailable"
            raise HTTPException(status_code=503, detail=detail, headers={"Retry-After": "2"}) from exc

        metrics.RETRIEVAL_LATENCY.observe(result.retrieval_s)
        metrics.LLM_LATENCY.labels(result.model, "ok").observe(result.llm_s)
        input_tokens = int(result.usage.get("input_tokens", 0))
        output_tokens = int(result.usage.get("output_tokens", 0))
        reasoning = int((result.usage.get("output_token_details") or {}).get("reasoning", 0))
        metrics.LLM_TOKENS.labels(result.model, "input").inc(input_tokens)
        metrics.LLM_TOKENS.labels(result.model, "output").inc(output_tokens)
        if reasoning:
            metrics.LLM_TOKENS.labels(result.model, "reasoning").inc(reasoning)
        metrics.LLM_COST.labels(result.model).inc(state.pricing.cost_usd(result.model, input_tokens, output_tokens))

        return RecommendResponse(
            recommendations=result.text,
            model=result.model,
            retrieved_titles=result.titles,
            trace_id=current_trace_id(),
        )

    return app


app = create_app()
