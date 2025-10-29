#!/usr/bin/env bash
set -euo pipefail
swift format --version >/dev/null 2>&1 || echo "swift-format not installed; skipping lint"
