#!/usr/bin/env bash
# Despliega en Vercel el resultado YA COMPILADO en local.
#
# Alternativa al build en Vercel, y para diagnosticar la más útil: elimina
# de la ecuación el clonado de Flutter y las variables de entorno del panel.
# Las claves quedan incrustadas en el bundle al compilar aquí, así que Vercel
# solo sirve archivos estáticos.
#
#   ./scripts/deploy_static.sh              # vista previa
#   ./scripts/deploy_static.sh --prod       # producción
#
# Contrapartida: no hay despliegue automático con cada push. Hay que ejecutar
# esto. Cuando el build en Vercel funcione, conviene volver a ese camino.
set -euo pipefail

cd "$(dirname "$0")/.."

PROD=""
[[ "${1:-}" == "--prod" ]] && PROD="--prod"

if [[ ! -f .env ]]; then
  echo "Falta .env — copia .env.example y complétalo." >&2
  exit 1
fi

set -a; source .env; set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_URL y SUPABASE_ANON_KEY deben estar en .env" >&2
  exit 1
fi

echo "──────────────────────────────────────────────────────────"
echo " 1/3 · Compilando en local"
echo "──────────────────────────────────────────────────────────"
FLUTTER_BIN=flutter bash scripts/vercel_build.sh

echo
echo "──────────────────────────────────────────────────────────"
echo " 2/3 · Preparando la carpeta para servir estático"
echo "──────────────────────────────────────────────────────────"

# El vercel.json de la raíz define un build; para un despliegue estático hace
# falta uno que solo declare las reescrituras y la caché, y debe vivir DENTRO
# de la carpeta que se sube.
cat > build/web/vercel.json <<'JSON'
{
    "rewrites": [
        {
            "source": "/(.*)",
            "destination": "/index.html"
        }
    ],
    "headers": [
        {
            "source": "/index.html",
            "headers": [
                { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
            ]
        },
        {
            "source": "/flutter_service_worker.js",
            "headers": [
                { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
            ]
        },
        {
            "source": "/flutter_bootstrap.js",
            "headers": [
                { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
            ]
        },
        {
            "source": "/assets/(.*)",
            "headers": [
                { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
            ]
        },
        {
            "source": "/canvaskit/(.*)",
            "headers": [
                { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
            ]
        }
    ]
}
JSON

echo "  vercel.json de estático escrito"
echo "  tamaño a subir: $(du -sh build/web | cut -f1)"

echo
echo "──────────────────────────────────────────────────────────"
echo " 3/3 · Subiendo a Vercel"
echo "──────────────────────────────────────────────────────────"
echo
echo "  Si es la primera vez pedirá iniciar sesión y confirmar el proyecto."
echo "  Responde:"
echo "    · Set up and deploy?            → yes"
echo "    · Which scope?                  → tu cuenta personal"
echo "    · Link to existing project?     → no (o sí, si ya lo creaste)"
echo "    · In which directory…?          → ./  (ya estamos dentro de build/web)"
echo "    · Want to modify the settings?  → no"
echo

cd build/web
exec npx --yes vercel@latest deploy $PROD
