#!/bin/bash
# Tests headless de Aria: logica pura, sin GUI ni audio ni cambio de foco.
# Los smoke tests de menubar/captura real viven aparte (ver PLAN.md).
cd "$(dirname "$0")/.." || exit 1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer exec swift test "$@"
