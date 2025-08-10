# Multi-stage Dockerfile for Control Plane

# Stage 1: Build stage
FROM oven/bun:1.1.0 AS builder

WORKDIR /app

# Copy package files
COPY package.json bun.lockb ./

# Install dependencies
RUN bun install --frozen-lockfile

# Copy source code
COPY . .

# Build TypeScript
RUN bun build ./src/index.ts --target=bun --outdir=./dist

# Stage 2: Runtime stage
FROM oven/bun:1.1.0-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

# Copy configuration files
COPY --from=builder /app/src/prompts/templates ./src/prompts/templates

# Create data directory for SQLite
RUN mkdir -p /app/data

# Environment variables
ENV NODE_ENV=production
ENV DATABASE_PATH=/app/data/control.db
ENV MCP_CONTEXT_PORT=9001
ENV MCP_MODEL_PORT=9002

# Expose ports
EXPOSE 3000 9001 9002

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Run as non-root user
RUN useradd -m -u 1001 appuser && chown -R appuser:appuser /app
USER appuser

# Start the application
CMD ["bun", "run", "dist/index.js"]