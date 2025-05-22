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

# 克隆 headscale
echo "Cloning headscale v${HEADSCALE_VERSION}..."
git clone --depth 1 --branch "v${HEADSCALE_VERSION}" https://github.com/juanfont/headscale.git "${TEMP_DIR}/headscale"

# 克隆 headplane
echo "Cloning headplane v${HEADPLANE_VERSION}..."
git clone --depth 1 --branch "${HEADPLANE_VERSION}" https://github.com/tale/headplane.git "${TEMP_DIR}/headplane"

# 复制文件
echo "Copying files..."
cp -r "${TEMP_DIR}/headscale" .
cp -r "${TEMP_DIR}/headplane" .

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