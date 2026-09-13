#!/usr/bin/env bash
# Recorre la PWA con un navegador de verdad y deja capturas.
set -euo pipefail

cd "$(dirname "$0")/../.."

ESCRIBIR="no"
[[ "${1:-}" == "--escribir" ]] && ESCRIBIR="si"

if [[ ! -f build/web/main.dart.js ]]; then
  echo "No hay build. Ejecuta ./scripts/build_web.sh primero." >&2
  exit 1
fi

# Las dependencias se instalan solas. Pedirlas en un README es garantizar que
# el primer intento falle con un error que no dice qué hacer.
if [[ ! -d scripts/e2e/node_modules ]]; then
  echo "Instalando Playwright (solo la primera vez)…"
  (cd scripts/e2e && npm install --silent)
fi

# Y el navegador, que va aparte del paquete.
if ! (cd scripts/e2e && npx playwright install chromium >/dev/null 2>&1); then
  echo "No se pudo instalar Chromium. Revisa la conexión." >&2
  exit 1
fi

# Las credenciales pueden estar en cualquiera de los dos sitios: el archivo
# propio de las pruebas o el `.env` del proyecto. Buscar en los dos evita la
# pregunta de en cuál tocaba ponerlas.
for archivo in scripts/e2e/.env.e2e .env; do
  if [[ -f "$archivo" ]]; then
    set -a; source "$archivo"; set +a
  fi
done

if [[ -z "${E2E_EMAIL:-}" ]]; then
  echo "Sin credenciales: solo se prueba la pantalla de acceso."
  echo "Para el resto, copia scripts/e2e/.env.e2e.example a .env.e2e."
  echo
fi

PUERTO="${E2E_PORT:-5199}"

# El servidor se levanta aquí y se apaga al terminar, pase lo que pase: un
# puerto ocupado por una ejecución anterior hace fallar la siguiente con un
# error que no dice nada de lo que de verdad ocurrió.
(cd build/web && python3 -m http.server "$PUERTO" >/dev/null 2>&1) &
SERVIDOR=$!
trap 'kill "$SERVIDOR" 2>/dev/null || true' EXIT

sleep 2
if ! curl -sf -o /dev/null "http://localhost:$PUERTO/"; then
  echo "El servidor local no responde en el puerto $PUERTO." >&2
  exit 1
fi

mkdir -p scripts/e2e/capturas
E2E_BASE="http://localhost:$PUERTO/" E2E_ESCRIBIR="$ESCRIBIR" \
  node scripts/e2e/recorrido.mjs

echo
echo "Capturas en scripts/e2e/capturas/"
