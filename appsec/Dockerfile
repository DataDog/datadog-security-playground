FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV UV_NO_DEV=1
ENV UV_LOCKED=1
ENV UV_COMPILE_BYTECODE=1
ENV UV_NO_EDITABLE=1
ENV UV_PROJECT_ENVIRONMENT=/usr/local

WORKDIR /app

COPY pyproject.toml uv.lock README.md ./
COPY src/ ./src/
RUN --mount=from=ghcr.io/astral-sh/uv,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync

ENV DOGFOODING_WEB_HOST=0.0.0.0
ENV DOGFOODING_WEB_PORT=8080

EXPOSE 8080

CMD ["start"]
