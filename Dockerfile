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

#FROM node:22-alpine
#WORKDIR /app
#COPY --from=headplane_build /app/build /app/build

# --- Build Stage 2: Build Headscale ---
FROM golang:1.24-alpine AS headscale_build
ARG VERSION
ARG VERSION_LONG
ARG VERSION_SHORT
ARG VERSION_GIT_HASH
ARG TARGETARCH=amd64
ARG BUILD_TAGS=""

ENV GOPATH=/go
ENV VERSION_LONG=$VERSION_LONG
ENV VERSION_SHORT=$VERSION_SHORT
ENV VERSION_GIT_HASH=$VERSION_GIT_HASH
ENV VERSION=$VERSION
ENV GOPROXY=https://goproxy.cn,direct

WORKDIR /go/src/headscale
RUN apk update \
    && apk add --no-cache git \
    && rm -rf /var/cache/apk/*

COPY headscale/go.mod headscale/go.sum ./
RUN go mod download
COPY headscale/ .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build \
    -tags="${BUILD_TAGS}" \
    -ldflags="-X github.com/juanfont/headscale/cmd/headscale/cli.Version=$VERSION \
              -X github.com/juanfont/headscale/cmd/headscale/cli.VersionLong=$VERSION_LONG \
              -X github.com/juanfont/headscale/cmd/headscale/cli.VersionShort=$VERSION_SHORT \
              -X github.com/juanfont/headscale/cmd/headscale/cli.VersionGitHash=$VERSION_GIT_HASH" \
    -o /go/bin/headscale ./cmd/headscale

# --- Final Stage: Combine and Run on Alpine with Certs ---
#FROM alpine:3.20 AS base
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

# Install acme.sh manually from tarball
ENV ACME_HOME="/app/acme.sh"
RUN mkdir -p "${ACME_HOME}" \
    && curl -L https://github.com/acmesh-official/acme.sh/archive/master.tar.gz | tar xz -C /app --one-top-level="${ACME_HOME}" --strip-components=1 \
    && chmod +x "${ACME_HOME}/acme.sh"

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
    /etc/letsencrypt

# Copy binaries and build output
COPY --from=headscale_build /go/bin/headscale /app/headscale/bin/headscale
RUN chmod +x /app/headscale/bin/headscale
COPY --from=headplane_build /app/build /app/headplane/build
COPY --from=headplane_build /app/package.json /app/headplane/
WORKDIR /app

# Copy configuration files and supervisord config
COPY configs/headscale.yaml /etc/headscale/config.yaml
COPY configs/headplane.yaml /etc/headplane/config.yaml
COPY supervisord.conf /etc/supervisord.conf

# Copy the certificate management script
COPY scripts/headplane.sh /app/scripts/headplane.sh
COPY scripts/cert_manager.sh /app/scripts/cert_manager.sh
RUN chmod +x /app/scripts/cert_manager.sh

# link haedscale and headplane
RUN ln -s /app/headscale/bin/headscale /usr/local/bin/headscale
RUN ln -s /app/scripts/headplane.sh /usr/local/bin/headplane
RUN chmod +x /app/scripts/headplane.sh

# Expose ports
EXPOSE 443/tcp 9000/tcp 80/tcp

# Define volumes
VOLUME /var/lib/headscale
VOLUME /etc/letsencrypt

# Entrypoint runs the script to process config and manage certs, then executes CMD
ENTRYPOINT ["/app/scripts/cert_manager.sh"]

# Default command is to run Supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
