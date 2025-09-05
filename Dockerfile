# Multi-stage build for Telegram Trading System (Go)

# -------- Builder stage --------
FROM golang:1.22-alpine AS builder

# Install build deps
RUN apk add --no-cache git ca-certificates tzdata && update-ca-certificates

WORKDIR /app

# Cache modules
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build static binary
ENV CGO_ENABLED=0
RUN go build -o /app/bin/server ./main.go

# -------- Runtime stage --------
FROM alpine:3.20

# Add certs and tzdata for HTTPS and correct time
RUN apk add --no-cache ca-certificates tzdata && update-ca-certificates

# Create non-root user and app dirs
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app

# Copy binary
COPY --from=builder /app/bin/server /app/server

# Create default data directory (override with MT4_DATA_PATH env)
RUN mkdir -p /data/mt4-files /app/mt4-files && chown -R app:app /data /app

# Environment (override as needed at runtime)
ENV PORT=":8080" \
    MT4_DATA_PATH="/data/mt4-files"

# Declare volume for host-mapped MT4 Common Files directory
VOLUME ["/data/mt4-files"]

# Expose HTTP port (container listens on :8080 by default)
EXPOSE 8080

# Drop privileges
USER app

# Run
ENTRYPOINT ["/app/server"]
