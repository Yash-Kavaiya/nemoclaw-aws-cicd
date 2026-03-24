# ─── Build stage ────────────────────────────────────────────────────────────
FROM node:20-bookworm-slim AS base

# Install system dependencies required by NemoClaw / OpenShell
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    wget \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install NemoClaw CLI globally
# NemoClaw is distributed as an npm package
RUN npm install -g nemoclaw

# Verify installation
RUN nemoclaw --version || true

# ─── Runtime stage ──────────────────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

# Copy installed global npm packages from base
COPY --from=base /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=base /usr/local/bin /usr/local/bin

# Install minimal runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r nemoclaw && useradd -r -g nemoclaw -m -d /home/nemoclaw nemoclaw

# Set working directory
WORKDIR /app

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# NemoClaw workspace (agent files, memory, etc. mount here)
RUN mkdir -p /app/workspace && chown -R nemoclaw:nemoclaw /app

USER nemoclaw

# NemoClaw gateway port
EXPOSE 3000

# Health check via HTTP
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Labels
ARG BUILD_DATE
ARG GIT_COMMIT
LABEL org.opencontainers.image.title="NemoClaw AWS"
LABEL org.opencontainers.image.description="NVIDIA NemoClaw on AWS ECS Fargate"
LABEL org.opencontainers.image.source="https://github.com/NVIDIA/NemoClaw"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"

ENTRYPOINT ["/entrypoint.sh"]
