#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SOURCE=${SOURCE:-/usr/bin/plutil}
REFERENCE_DIR=${REFERENCE_DIR:-${SCRIPT_DIR}/reference}

GENERATE_REFERENCE=1 \
SOURCE="${SOURCE}" \
REFERENCE_DIR="${REFERENCE_DIR}" \
sh "${SCRIPT_DIR}/regression.sh"
