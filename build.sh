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

# 下载 headscale 二进制文件
echo "Downloading headscale ${HEADSCALE_VERSION}..."
if ! wget -O "${TEMP_DIR}/headscale" "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_amd64" 2>/dev/null; then
    echo "Error: Failed to download headscale ${HEADSCALE_VERSION}"
    exit 1
fi
chmod +x "${TEMP_DIR}/headscale"
mkdir -p headscale/bin
cp "${TEMP_DIR}/headscale" headscale/bin/

# 检查并克隆 headplane
echo "Checking headplane repository..."
if [ ! -d "headplane" ]; then
    echo "Cloning headplane ${HEADPLANE_VERSION}..."
    if ! git clone --depth 1 --branch "${HEADPLANE_VERSION}" https://github.com/tale/headplane.git "${TEMP_DIR}/headplane" 2>/dev/null; then
        echo "Tag ${HEADPLANE_VERSION} not found, trying v${HEADPLANE_VERSION}..."
        if ! git clone --depth 1 --branch "v${HEADPLANE_VERSION}" https://github.com/tale/headplane.git "${TEMP_DIR}/headplane" 2>/dev/null; then
            echo "Error: Could not find tag ${HEADPLANE_VERSION} or v${HEADPLANE_VERSION}"
            exit 1
        fi
    fi
    cp -r "${TEMP_DIR}/headplane" .
else
    echo "Headplane repository already exists, updating..."
    cd headplane
    if ! git fetch origin "${HEADPLANE_VERSION}" 2>/dev/null; then
        echo "Tag ${HEADPLANE_VERSION} not found, trying v${HEADPLANE_VERSION}..."
        if ! git fetch origin "v${HEADPLANE_VERSION}" 2>/dev/null; then
            echo "Error: Could not find tag ${HEADPLANE_VERSION} or v${HEADPLANE_VERSION}"
            exit 1
        fi
        git checkout "v${HEADPLANE_VERSION}"
    else
        git checkout "${HEADPLANE_VERSION}"
    fi
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
    -t "headscale-headplane:hp${HEADPLANE_VERSION}-hs${HEADSCALE_VERSION}" .

echo "Build completed!" 