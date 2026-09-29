#!/bin/bash
set -e

# Fail fast on missing prerequisites rather than after a multi-hour compile
for cmd in docker zip; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: '${cmd}' is required but not found in PATH." >&2
        exit 1
    fi
done
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon is not running or not reachable." >&2
    exit 1
fi

DEFCONFIG="k6core_gui_defconfig"
VOLUME_NAME="k6core-gui-build-cache"
DISK_IMAGE="disk-gui.img"
ZIP_NAME="k6core-gui-latest.img.zip"

# Define image and volume names
IMAGE_NAME="k6core-builder"

echo "=== Building K6Core (defconfig: ${DEFCONFIG}) ==="

echo "=== Checking Docker Volume: ${VOLUME_NAME} ==="
if ! docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
    echo "Creating persistent volume: ${VOLUME_NAME}"
    docker volume create "${VOLUME_NAME}"
else
    echo "Persistent volume: ${VOLUME_NAME} already exists."
fi

echo "=== Building Builder Docker Image: ${IMAGE_NAME} ==="
docker build -t "${IMAGE_NAME}" .

echo "=== Starting Buildroot Compilation ==="
docker run --rm \
    -v "${VOLUME_NAME}":/root/buildroot-output \
    -v "$(pwd)":/workspace \
    -e FORCE_UNSAFE_CONFIGURE=1 \
    "${IMAGE_NAME}" \
    /bin/bash -c "
        echo '=== Initializing Buildroot Defconfig ===' && \
        make -C /buildroot O=/root/buildroot-output defconfig BR2_DEFCONFIG=/workspace/configs/${DEFCONFIG} && \
        echo '=== Compilation Started ===' && \
        make -C /buildroot O=/root/buildroot-output && \
        echo '=== Compilation Completed successfully! ===' && \
        cp /root/buildroot-output/images/disk.img /workspace/${DISK_IMAGE} && \
        echo '=== Copied disk.img to workspace as ${DISK_IMAGE} ==='
    "

echo "=== Compressing ${DISK_IMAGE} into ${ZIP_NAME} ==="
rm -f "${ZIP_NAME}"
zip -j "${ZIP_NAME}" "${DISK_IMAGE}"
echo "=== Compressed image ready: ${ZIP_NAME} ==="
