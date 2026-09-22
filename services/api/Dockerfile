# syntax=docker/dockerfile:1.7
# Build context: repository root.  docker build -f services/api/Dockerfile .

# ---- builder: locked API dependencies into /app/.venv ----
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-default-groups --group api --no-install-project

# ---- index: embed the catalogue and refuse to continue if the index is incomplete ----
FROM builder AS index
ARG EMBEDDINGS_PROVIDER=hf
ARG EXPECTED_DOCS=269
ENV PATH=/app/.venv/bin:$PATH PYTHONPATH=/app/src HF_HOME=/tmp/hf ANONYMIZED_TELEMETRY=False \
    EXPECTED_DOCS=${EXPECTED_DOCS}
COPY src ./src
COPY data/anime_with_synopsis.csv ./data/
RUN --mount=type=secret,id=hf_token,required=false \
    HF_TOKEN="$(cat /run/secrets/hf_token 2>/dev/null || true)" \
    python -m anime.index build --out /index --embeddings "$EMBEDDINGS_PROVIDER"

# ---- test: lint + unit tests (docker build -f services/api/Dockerfile --target test .) ----
FROM builder AS test
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project
ENV PATH=/app/.venv/bin:$PATH ANONYMIZED_TELEMETRY=False
COPY pyproject.toml ./
COPY config ./config
COPY data ./data
COPY src ./src
COPY services ./services
COPY tests ./tests
RUN ruff check src services tests && pytest -q

# ---- runtime ----
FROM python:3.12-slim-bookworm AS runtime
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONPATH=/app/src:/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/tmp \
    HF_HOME=/tmp/hf \
    ANONYMIZED_TELEMETRY=False \
    INDEX_DIR=/app/index
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY src ./src
COPY services/__init__.py ./services/
COPY services/api ./services/api
COPY data/prompt_template.txt ./data/
COPY config/pricing.yaml ./config/
COPY --from=index /index ./index
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=30s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"
CMD ["uvicorn", "services.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
