#!/bin/sh
set -e

# 检查参数
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <headplane_version> <headscale_version>"
    echo "Example: $0 1.0.0 0.22.3"
    exit 1
fi

HEADPLANE_VERSION=$1
HEADSCALE_VERSION=$2

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 检查并克隆 headscale
echo "Checking headscale repository..."
if [ ! -d "headscale" ]; then
    echo "Cloning headscale v${HEADSCALE_VERSION}..."
    git clone --depth 1 --branch "v${HEADSCALE_VERSION}" https://github.com/juanfont/headscale.git "${TEMP_DIR}/headscale"
    cp -r "${TEMP_DIR}/headscale" .
else
    echo "Headscale repository already exists, updating..."
    cd headscale
    git fetch origin "v${HEADSCALE_VERSION}"
    git checkout "v${HEADSCALE_VERSION}"
    cd ..
fi

# 检查并克隆 headplane
echo "Checking headplane repository..."
if [ ! -d "headplane" ]; then
    echo "Cloning headplane v${HEADPLANE_VERSION}..."
    git clone --depth 1 --branch "${HEADPLANE_VERSION}" https://github.com/tale/headplane.git "${TEMP_DIR}/headplane"
    cp -r "${TEMP_DIR}/headplane" .
else
    echo "Headplane repository already exists, updating..."
    cd headplane
    git fetch origin "${HEADPLANE_VERSION}"
    git checkout "${HEADPLANE_VERSION}"
    cd ..
fi

# 构建 Docker 镜像
echo "Building Docker image..."
docker build \
    --build-arg VERSION="headplane-${HEADPLANE_VERSION}-headscale-${HEADSCALE_VERSION}" \
    --build-arg VERSION_LONG="headplane-${HEADPLANE_VERSION}-headscale-${HEADSCALE_VERSION}" \
    --build-arg VERSION_SHORT="headplane-${HEADPLANE_VERSION}-headscale-${HEADSCALE_VERSION}" \
    --build-arg VERSION_GIT_HASH="stable" \
    --build-arg HEADPLANE_VERSION="${HEADPLANE_VERSION}" \
    --build-arg HEADSCALE_VERSION="${HEADSCALE_VERSION}" \
    -t "headscale:hp${HEADPLANE_VERSION}-hs${HEADSCALE_VERSION}" .

echo "Build completed!" 