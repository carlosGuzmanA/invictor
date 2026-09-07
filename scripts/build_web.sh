#!/usr/bin/env bash
# Compila la PWA para producción -> build/web (desplegable en Vercel)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Falta .env — copia .env.example y complétalo." >&2
  exit 1
fi

set -a; source .env; set +a

flutter build web \
  --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=STORAGE_BUCKET="${STORAGE_BUCKET:-inventory}"

echo
echo "Listo -> build/web"
echo "Probar localmente:  cd build/web && python3 -m http.server 5173"
