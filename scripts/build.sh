#!/bin/bash
# Build con el MISMO toolchain que scripts/test.sh (swiftc de Xcode.app).
# Mezclar CLT y Xcode sobre el mismo .build deja .o incompatibles (p.ej. _swift_coroFrameAlloc).
cd "$(dirname "$0")/.." || exit 1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer exec swift build "$@"
