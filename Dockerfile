# syntax=docker/dockerfile:1

# Frontend build stage
FROM oven/bun:1 AS frontend-builder

WORKDIR /app

# Copy frontend source code
COPY lightrag_webui/ ./lightrag_webui/

# Build frontend assets for inclusion in the API package
#RUN --mount=type=cache,target=/root/.bun/install/cache \
#   cd lightrag_webui \
#   && bun install --frozen-lockfile \
#   && bun run build
RUN cd lightrag_webui \
    && bun install --frozen-lockfile \
    && bun run build


# Python build stage - using uv for faster package installation
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive
# Use uv-managed virtualenv in /app/.venv (default).
# NOTE: Do NOT force system python here; Cloud Run runtime should use /app/.venv.
ENV UV_SYSTEM_PYTHON=0
ENV UV_COMPILE_BYTECODE=1

WORKDIR /app

# Install system deps (Rust is required by some wheels)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        build-essential \
        pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:/root/.local/bin:${PATH}"

# Ensure shared data directory exists for uv caches
RUN mkdir -p /root/.local/share/uv

# Copy project metadata and sources
COPY pyproject.toml .
COPY setup.py .
COPY uv.lock .

# Install base, API, and offline extras without the project to improve caching
RUN uv sync --frozen --no-dev --extra api --extra offline --no-install-project --no-editable

# Copy project sources after dependency layer
COPY lightrag/ ./lightrag/

# Include pre-built frontend assets from the previous stage
COPY --from=frontend-builder /app/lightrag/api/webui ./lightrag/api/webui

# Sync project in non-editable mode and ensure pip is available for runtime installs
RUN uv sync --frozen --no-dev --extra api --extra offline --no-editable \
    && /app/.venv/bin/python -m ensurepip --upgrade

# Prepare offline cache directory and pre-populate tiktoken data
# Use uv run to execute commands from the virtual environment
RUN mkdir -p /app/data/tiktoken \
    && uv run lightrag-download-cache --cache-dir /app/data/tiktoken || status=$?; \
    if [ -n "${status:-}" ] && [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then exit "$status"; fi

# Final stage
# IMPORTANT: The runtime base image MUST match the builder image's Python layout.
# We copy /app/.venv from the uv builder image; if we switch to python:3.12-slim,
# the venv's interpreter symlink can break ("/app/.venv/bin/python: no such file").
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

# Use the copied uv-managed virtualenv at /app/.venv.
ENV UV_SYSTEM_PYTHON=0

# Copy installed packages and application code
COPY --from=builder /root/.local /root/.local
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/lightrag ./lightrag
COPY pyproject.toml .
COPY setup.py .
COPY uv.lock .

# Ensure the installed scripts are on PATH
ENV PATH=/app/.venv/bin:/root/.local/bin:$PATH

# Cloud Run may not honor WORKDIR for module resolution in all cases.
# Ensure the application source directory is always importable.
ENV PYTHONPATH=/app

# Dependencies + project are already installed into /app/.venv in the builder stage.
# Running `uv sync` again in the runtime stage can inadvertently mutate/remove the venv.

# Fail the image build early if the app package cannot be imported from the venv.
RUN /app/.venv/bin/python -c "import lightrag; print('LightRAG import OK:', lightrag.__file__)"

# Create persistent data directories AFTER package installation
RUN mkdir -p /app/data/rag_storage /app/data/inputs /app/data/tiktoken

# Copy offline cache into the newly created directory
COPY --from=builder /app/data/tiktoken /app/data/tiktoken

# Point to the prepared cache
ENV TIKTOKEN_CACHE_DIR=/app/data/tiktoken
ENV WORKING_DIR=/app/data/rag_storage
ENV INPUT_DIR=/app/data/inputs

# Expose API port
EXPOSE 9621

# IMPORTANT: Always run using the virtualenv interpreter.
# Cloud Run logs showed `/usr/local/bin/python` failing to import `lightrag`,
# which indicates the system interpreter is being used. Running the venv
# interpreter ensures both dependencies and the project package are on sys.path.
ENTRYPOINT ["/app/.venv/bin/python", "-m", "lightrag.api.lightrag_server"]
