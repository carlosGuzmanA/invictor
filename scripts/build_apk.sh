#!/usr/bin/env bash
# Genera el APK para distribuir por enlace directo (§13)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Falta .env — copia .env.example y complétalo." >&2
  exit 1
fi

set -a; source .env; set +a

flutter build apk \
  --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=STORAGE_BUCKET="${STORAGE_BUCKET:-inventory}"

echo
echo "APK -> build/app/outputs/flutter-apk/app-release.apk"
echo "Súbelo a tu hosting como inventario.apk y compártelo por enlace."
