# --- Build Stage 1: Build Headplane ---
FROM node:22-alpine AS headplane_build
WORKDIR /app
RUN apk add --no-cache git \
    && npm install -g pnpm@10 \
    && rm -rf /tmp/* /var/cache/apk/* \
    && pnpm config set registry https://registry.npmmirror.com/ \
    && pnpm config set network-timeout 100000 \
    && pnpm config set fetch-retries 5
ENV PATH="/root/.local/share/pnpm:${PATH}"
COPY ./headplane/package.json ./headplane/pnpm-lock.yaml ./
COPY ./headplane/patches ./patches
RUN pnpm install --frozen-lockfile
COPY ./headplane/. .
RUN pnpm run build

# --- Build Stage 2: Build Caddy with Cloudflare plugin ---
FROM golang:1.24-alpine AS caddy_build
RUN apk add --no-cache git
ENV GOPROXY=https://goproxy.cn,direct
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare@latest

# --- Final Stage: Combine and Run on Alpine with Caddy ---
FROM node:22-alpine AS base

# Install runtime dependencies
RUN apk update && apk add --no-cache \
    supervisor \
    nodejs \
    sqlite \
    curl \
    socat \
    tar \
    gzip \
    gettext \
    ca-certificates \
    iptables \
    iproute2 \
    ip6tables \
    && rm -rf /var/cache/apk/*

# Copy custom Caddy binary
COPY --from=caddy_build /go/caddy /usr/bin/caddy

# Create necessary directories
RUN mkdir -p /etc/headscale \
    /etc/headplane \
    /var/lib/headscale \
    /var/lib/headplane \
    /app/headscale \
    /app/headplane \
    /app/scripts \
    /var/log/supervisor \
    /var/run/headscale \
    /etc/caddy

# Copy binaries and build output
COPY ./headscale/bin/headscale /app/headscale/bin/headscale
RUN chmod +x /app/headscale/bin/headscale
COPY --from=headplane_build /app/build /app/headplane/build
COPY --from=headplane_build /app/package.json /app/headplane/
WORKDIR /app

# Copy configuration files and supervisord config
COPY configs/headscale.yaml /etc/headscale/config.yaml
COPY configs/headplane.yaml /etc/headplane/config.yaml
COPY supervisord.conf /etc/supervisord.conf
COPY Caddyfile /etc/caddy/Caddyfile

# Copy the scripts
COPY scripts/headplane.sh /app/scripts/headplane.sh
RUN chmod +x /app/scripts/headplane.sh

# link headscale and headplane
RUN ln -s /app/headscale/bin/headscale /usr/local/bin/headscale
RUN ln -s /app/scripts/headplane.sh /usr/local/bin/headplane

# Expose ports
EXPOSE 443/tcp 3000/tcp 3478/udp 50443/tcp

# Define volumes
VOLUME /var/lib/headscale
VOLUME /etc/headscale
VOLUME /etc/headplane
VOLUME /etc/caddy

# Default command is to run Supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
