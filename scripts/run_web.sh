#!/usr/bin/env bash
# Levanta la app en Chrome leyendo las variables desde .env
#
# Puerto: 5173 por defecto. NO se usa el 5000 porque en macOS lo ocupa
# AirPlay Receiver (ControlCenter) desde Monterey.
# Se puede forzar otro:  WEB_PORT=8080 ./scripts/run_web.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Falta .env — copia .env.example y complétalo:" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

set -a; source .env; set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL y SUPABASE_ANON_KEY deben estar definidas en .env" >&2
  exit 1
fi

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

PORT="${WEB_PORT:-5173}"

# Si el puerto elegido está ocupado, buscar el siguiente libre en vez de
# fallar con un stack trace de SocketException.
if port_busy "$PORT"; then
  echo "Puerto $PORT ocupado por: $(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -Fc 2>/dev/null | sed -n 's/^c//p' | head -1)"
  for candidate in 5173 5174 5175 8080 8000 4200 3000; do
    if ! port_busy "$candidate"; then
      PORT="$candidate"
      echo "Usando el puerto $PORT."
      break
    fi
  done
fi

if port_busy "$PORT"; then
  echo "No se encontró un puerto libre. Indica uno:  WEB_PORT=9123 $0" >&2
  exit 1
fi

echo "InVictor -> http://localhost:${PORT}"

exec flutter run -d chrome \
  --web-port="${PORT}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=STORAGE_BUCKET="${STORAGE_BUCKET:-inventory}"
