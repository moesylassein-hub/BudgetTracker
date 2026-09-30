#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed or not on PATH. Use Flutter 3.44.0 or newer stable."
  exit 1
fi

if [ ! -f android/key.properties ]; then
  echo "Missing android/key.properties. Create your upload key before building a Play release."
  exit 1
fi

flutter --version
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release

echo
echo "Release checks passed."
echo "AAB: build/app/outputs/bundle/release/app-release.aab"
