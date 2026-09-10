#!/usr/bin/env bash
# Verifica que no haya credenciales a punto de subirse a un repositorio
# público. Ejecutar ANTES de cada push:
#
#   ./scripts/check_secrets.sh
#
# Devuelve 1 si encuentra algo, para poder usarlo en un hook o en CI.
set -uo pipefail

cd "$(dirname "$0")/.."

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
problems=0

fail() { echo "${RED}✗${OFF} $1"; problems=$((problems + 1)); }
warn() { echo "${YELLOW}!${OFF} $1"; }
ok()   { echo "${GREEN}✓${OFF} $1"; }

echo "Comprobando secretos antes de publicar…"
echo

# --- ¿Estamos en un repositorio? -------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git=1
else
  in_git=0
  warn "Todavía no hay repositorio git; la lista de archivos se aproxima."
fi

# --- Archivos que DE VERDAD se publicarían ---------------------------------
#
# Escanear todo el disco daba falsos positivos con .env, que es justo donde
# las credenciales SÍ deben estar. Lo que importa es qué llegaría al repo.
if [[ $in_git -eq 1 ]]; then
  FILES=$(git ls-files --cached --others --exclude-standard)
else
  FILES=$(find . -type f \
    -not -path './.git/*' \
    -not -path './build/*' \
    -not -path './.dart_tool/*' \
    -not -name '.env' \
    -not -name '.env.*' \
    -not -name '*.jks' \
    -not -name '*.keystore' \
    -not -name 'key.properties' \
    | sed 's|^\./||')
fi

# Busca un patrón solo en los archivos publicables.
scan() {
  local pattern="$1"
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] || continue
    case "$f" in
      *check_secrets.sh|*.example|*SEGURIDAD.md|*.md) continue ;;
    esac
    grep -InE "$pattern" "$f" 2>/dev/null | sed "s|^|$f:|"
  done
}

# --- 1. Archivos que nunca deben estar rastreados --------------------------
if [[ $in_git -eq 1 ]]; then
  tracked_bad=0
  for pattern in '.env' '*.jks' '*.keystore' 'key.properties' \
                 'google-services.json' '*.p12' '*.pem'; do
    hit=$(git ls-files "$pattern" 2>/dev/null)
    if [[ -n "$hit" ]]; then
      fail "rastreado por git: $hit"
      tracked_bad=1
    fi
  done

  # El JavaScript compilado lleva dentro la URL y la anon key.
  if git ls-files 'build/*' 2>/dev/null | grep -q .; then
    fail "la carpeta build/ está rastreada: contiene las claves compiladas"
    tracked_bad=1
  fi

  [[ $tracked_bad -eq 0 ]] && ok "ningún archivo sensible rastreado"
fi

# --- 2. .env debe estar ignorado -------------------------------------------
if [[ -f .env ]]; then
  if [[ $in_git -eq 1 ]]; then
    if git check-ignore -q .env; then
      ok ".env está ignorado (sus credenciales no se subirán)"
    else
      fail ".env NO está ignorado y contiene tus credenciales"
    fi
  fi
else
  warn "no hay .env local (normal si aún no lo has creado)"
fi

# --- 3. Tokens JWT en archivos publicables ---------------------------------
# La anon key es pública por diseño, pero incrustarla impide cambiarla sin
# recompilar y la deja en el historial de git para siempre.
jwt=$(scan 'eyJ[A-Za-z0-9_-]{20,}\.' | head -5)
if [[ -n "$jwt" ]]; then
  fail "posible token JWT en un archivo que se subiría:"
  printf '%s\n' "$jwt" | sed 's/^/    /'
else
  ok "ningún token JWT en archivos publicables"
fi

# --- 4. La service_role key jamás debe aparecer ----------------------------
# Da acceso total saltándose RLS. En el cliente, anula toda la seguridad.
svc=$(scan 'service_?role' | grep -viE 'nunca|never|no debe|jamás' | head -5)
if [[ -n "$svc" ]]; then
  fail "se menciona service_role fuera de una advertencia:"
  printf '%s\n' "$svc" | sed 's/^/    /'
else
  ok "sin referencias a service_role"
fi

# --- 5. La URL del proyecto incrustada -------------------------------------
url=$(scan 'https://[a-z0-9]{15,}\.supabase\.co' | head -5)
if [[ -n "$url" ]]; then
  fail "URL de proyecto Supabase incrustada:"
  printf '%s\n' "$url" | sed 's/^/    /'
else
  ok "sin URL de Supabase incrustada"
fi

# --- 6. Contraseñas en texto claro -----------------------------------------
pwd_hits=$(scan '(password|contrasena)[[:space:]]*[:=][[:space:]]*.{6,}' \
  | grep -viE 'labelText|hintText|Validators|_passwordCtrl|password:|obscure' \
  | grep -viE 'must_change_password|newPassword|body\.password|generatePassword' \
  | head -5)
if [[ -n "$pwd_hits" ]]; then
  warn "revisar posibles contraseñas en texto claro:"
  printf '%s\n' "$pwd_hits" | sed 's/^/    /'
else
  ok "sin contraseñas en texto claro"
fi

echo
if [[ $problems -gt 0 ]]; then
  echo "${RED}$problems problema(s).${OFF} No subas nada hasta resolverlos."
  echo
  echo "Si ya hiciste commit de un secreto, borrarlo en un commit nuevo NO"
  echo "basta: sigue en el historial. Hay que reescribirlo (git filter-repo)"
  echo "y, sobre todo, ROTAR la credencial expuesta en Supabase."
  exit 1
fi

echo "${GREEN}Sin problemas.${OFF} Recuerda además, en Supabase:"
echo "  · Authentication → Sign In / Providers: desactivar el registro público"
echo "  · Authentication → URL Configuration: añadir tu dominio de Vercel"
echo "  Ver docs/SEGURIDAD.md"
