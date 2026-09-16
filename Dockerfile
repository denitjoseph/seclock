# ─── Stage 1: Builder ────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies into a prefix directory
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --prefix=/install --no-cache-dir -r requirements.txt


# ─── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

LABEL maintainer="Seclock Dev Team"
LABEL description="Seclock — Legally-Aware Digital Inheritance & Emergency Access Vault"
LABEL version="1.0.0"

# Create a non-root user for security
RUN useradd --no-create-home --shell /bin/false seclock

WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /install /usr/local

# Copy application source
COPY --chown=seclock:seclock . .

# Create required directories with correct permissions
RUN mkdir -p static sample_certificates && \
    chown -R seclock:seclock /app

# Switch to non-root user
USER seclock

# Expose the application port
EXPOSE 8000

# Health check — pings the API state endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/state')" || exit 1

# Start the Uvicorn server
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
