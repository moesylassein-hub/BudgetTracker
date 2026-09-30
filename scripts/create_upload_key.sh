#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYSTORE="$ROOT_DIR/android/upload-keystore.jks"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool was not found. Install a JDK (17 or newer) and try again."
  exit 1
fi

if [ -f "$KEYSTORE" ]; then
  echo "A keystore already exists at: $KEYSTORE"
  echo "Refusing to overwrite it."
  exit 1
fi

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload

echo
echo "Created: $KEYSTORE"
echo "Now copy android/key.properties.example to android/key.properties and enter the same passwords."
echo "Back up the keystore and passwords securely."
