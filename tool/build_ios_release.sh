#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYMBOL_DIR="${ROOT}/build/symbols/ios"

cd "${ROOT}"
mkdir -p "${SYMBOL_DIR}"

flutter pub get
flutter build ipa \
  --release \
  --obfuscate \
  --split-debug-info="${SYMBOL_DIR}" \
  "$@"

printf '\nRelease IPA: %s\n' "${ROOT}/build/ios/ipa"
printf 'Debug symbols: %s\n' "${SYMBOL_DIR}"
printf '请单独备份 Debug symbols，后续符号化线上崩溃时需要。\n'
