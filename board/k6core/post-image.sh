#!/bin/sh
set -e

BOARD_DIR="$(dirname "$0")"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"

echo "=== Running K6Core Post-Image Script ==="
echo "Invoking Buildroot standard genimage.sh with configuration: ${GENIMAGE_CFG}"

# Execute Buildroot's official genimage.sh script to compile partitions and MBR boot sector
bash support/scripts/genimage.sh -c "${GENIMAGE_CFG}"

echo "=== K6Core Post-Image Script Complete ==="
