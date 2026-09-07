#!/usr/bin/env bash
# Despliega en Vercel el resultado YA COMPILADO en local.
#
# Alternativa al build en Vercel, y para diagnosticar la más útil: elimina
# de la ecuación el clonado de Flutter y las variables de entorno del panel.
# Las claves quedan incrustadas en el bundle al compilar aquí, así que Vercel
# solo sirve archivos estáticos.
#
#   ./scripts/deploy_static.sh --temporary  # URL inmediata, sin cuenta
#   ./scripts/deploy_static.sh              # vista previa (requiere sesión)
#   ./scripts/deploy_static.sh --prod       # producción (requiere sesión)
#
# Contrapartida: no hay despliegue automático con cada push. Hay que ejecutar
# esto. Cuando el build en Vercel funcione, conviene volver a ese camino.
set -euo pipefail

cd "$(dirname "$0")/.."

PROD=""
TEMP=0
case "${1:-}" in
  --prod)      PROD="--prod" ;;
  # Despliegue temporal: da una URL sin necesidad de cuenta, reclamable
  # después desde el panel. Sirve para probar en el teléfono en un minuto.
  --temporary) TEMP=1 ;;
esac

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

# El vínculo con el proyecto de Vercel vive en la raíz y se copia dentro.
# `flutter build web` limpia build/, así que guardarlo ahí se perdería en
# cada compilación y el CLI preguntaría de nuevo — creando un proyecto
# distinto cada vez y un dominio nuevo.
if [[ -d .vercel ]]; then
  cp -R .vercel build/web/.vercel
  echo "  vínculo con el proyecto existente restaurado"
else
  echo "  sin vínculo previo: el CLI preguntará el nombre del proyecto"
fi

echo "  tamaño a subir: $(du -sh build/web | cut -f1)"

echo
echo "──────────────────────────────────────────────────────────"
echo " 3/3 · Subiendo a Vercel"
echo "──────────────────────────────────────────────────────────"

# Se fija la versión del CLI: `@latest` descarga una distinta cada vez y un
# cambio de comportamiento entre versiones rompería este script sin aviso.
VERCEL="npx --yes vercel@59"

if [[ $TEMP -eq 1 ]]; then
  echo
  echo "  Modo temporal: sin iniciar sesión."
  echo "  Da una URL inmediata que podrás reclamar luego desde el panel."
  echo
  cd build/web
  exec $VERCEL deploy --temporary
fi

# El CLI no inicia sesión por su cuenta al desplegar: falla con
# "No existing credentials found". Se comprueba antes.
echo
if $VERCEL whoami >/dev/null 2>&1; then
  echo "  Sesión activa como: $($VERCEL whoami 2>/dev/null | tail -1)"
else
  echo "  Sin sesión en Vercel. Iniciando…"
  echo
  echo "  Elige GitHub y entra con la cuenta carlosGuzmanA."
  echo "  Si el navegador ya tiene otra sesión abierta, usa una ventana"
  echo "  privada: se autenticaría con la cuenta equivocada."
  echo
  $VERCEL login
  echo
  if ! $VERCEL whoami >/dev/null 2>&1; then
    echo "El login no se completó. Vuelve a ejecutar el script." >&2
    exit 1
  fi
  echo "  Sesión iniciada como: $($VERCEL whoami 2>/dev/null | tail -1)"
fi

echo
echo "  Responde a las preguntas del despliegue:"
echo "    · Set up and deploy?            → yes"
echo "    · Which scope?                  → tu cuenta personal"
echo "    · Link to existing project?     → no"
echo "    · Project name?                 → invictor-app"
echo "    · In which directory…?          → ./  (ya estamos dentro de build/web)"
echo "    · Want to modify the settings?  → no"
echo

cd build/web
$VERCEL deploy $PROD

# Se guarda el vínculo en la raíz para que el siguiente despliegue vaya al
# MISMO proyecto y conserve el dominio.
cd ..
cd ..
if [[ -d build/web/.vercel ]]; then
  rm -rf .vercel
  cp -R build/web/.vercel .vercel
  name=$(python3 -c "import json;print(json.load(open('.vercel/project.json')).get('projectName','?'))" 2>/dev/null || echo '?')
  echo
  echo "  Vínculo guardado. Proyecto: $name"
  echo "  Los próximos despliegues irán al mismo y mantendrán el dominio."
fi
