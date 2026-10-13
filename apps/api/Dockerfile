FROM ghcr.io/astral-sh/uv:0.13.0 AS uv
FROM python:3.12-slim AS base
COPY --from=uv /uv /usr/local/bin/uv
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 UV_LINK_MODE=copy
WORKDIR /app
COPY apps/api/pyproject.toml apps/api/uv.lock ./

FROM base AS test
RUN uv sync --locked
COPY apps/api/app app
COPY apps/api/tests tests
CMD ["uv", "run", "--no-sync", "pytest"]

FROM base AS runtime
RUN uv sync --locked --no-dev && useradd --uid 10001 --create-home suni
COPY apps/api/app app
ENV PATH="/app/.venv/bin:$PATH"
USER suni
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-proxy-headers"]
