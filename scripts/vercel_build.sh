#!/usr/bin/env bash
# Build de producción para Vercel.
#
# Existe en lugar de poner el comando directamente en vercel.json por una
# razón concreta: si las variables de entorno no llegan, `--dart-define` las
# incrusta como cadena vacía y el despliegue **funciona** — publica una
# aplicación que arranca y muestra "No se pudo conectar con Supabase".
#
# Un fallo silencioso en el build es peor que uno ruidoso: obliga a
# diagnosticar desde el navegador algo que el log ya sabía. Aquí el build
# falla, y el log de Vercel dice exactamente qué falta.
set -euo pipefail

FLUTTER="${FLUTTER_BIN:-_flutter/bin/flutter}"

echo "──────────────────────────────────────────────────────────"
echo " InVictor · build web"
echo "──────────────────────────────────────────────────────────"

# --- Comprobación de variables --------------------------------------------
missing=()
[[ -z "${SUPABASE_URL:-}" ]]      && missing+=("SUPABASE_URL")
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing+=("SUPABASE_ANON_KEY")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo
  echo "ERROR: faltan variables de entorno: ${missing[*]}"
  echo
  echo "El build se detiene a propósito. Sin ellas se publicaría una"
  echo "aplicación que arranca y no puede conectarse a la base de datos."
  echo
  echo "Cómo resolverlo en Vercel:"
  echo "  1. Project Settings → Environment Variables"
  echo "  2. Añadir SUPABASE_URL, SUPABASE_ANON_KEY y STORAGE_BUCKET"
  echo "  3. Marcar las tres para Production, Preview y Development"
  echo "  4. Deployments → ⋮ → Redeploy, DESMARCANDO 'Use existing Build Cache'"
  echo
  echo "Las variables se incrustan al COMPILAR (--dart-define), no se leen"
  echo "al arrancar: añadirlas sin volver a compilar no cambia nada."
  echo
  exit 1
fi

# Se informa de longitudes, no de valores: el log de Vercel es visible para
# cualquiera con acceso al proyecto.
echo "  SUPABASE_URL      : ${#SUPABASE_URL} caracteres"
echo "  SUPABASE_ANON_KEY : ${#SUPABASE_ANON_KEY} caracteres"
echo "  STORAGE_BUCKET    : ${STORAGE_BUCKET:-inventory}"

# Un error de copiado frecuente: pegar la clave con saltos de línea o espacios.
if [[ "$SUPABASE_URL" != https://*.supabase.co* ]]; then
  echo
  echo "ERROR: SUPABASE_URL no tiene la forma https://xxxx.supabase.co"
  echo "       Revisa que no lleve espacios ni comillas alrededor."
  exit 1
fi

if [[ ${#SUPABASE_ANON_KEY} -lt 100 ]]; then
  echo
  echo "ERROR: SUPABASE_ANON_KEY parece truncada (${#SUPABASE_ANON_KEY} caracteres)."
  echo "       Una anon key completa ronda los 200. Vuelve a copiarla entera."
  exit 1
fi

echo
echo "Compilando…"
"$FLUTTER" build web \
  --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=STORAGE_BUCKET="${STORAGE_BUCKET:-inventory}"

# --- Verificación del resultado -------------------------------------------
# Comprueba que las claves quedaron DENTRO del bundle. Si el build reutilizó
# caché o el dart-define no se aplicó, esto lo detecta antes de publicar.
host=$(printf '%s' "$SUPABASE_URL" | sed -E 's#https://([^.]+)\..*#\1#')
if ! grep -q "$host" build/web/main.dart.js 2>/dev/null; then
  echo
  echo "ERROR: el bundle compilado no contiene la URL de Supabase."
  echo "       El --dart-define no se aplicó, o se reutilizó un build en caché."
  echo "       Redespliega desmarcando 'Use existing Build Cache'."
  exit 1
fi

echo
echo "✓ Build correcto y con la configuración incrustada."
