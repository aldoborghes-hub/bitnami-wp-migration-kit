#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: 99_crear_admin_wp.sh
# Desarrollado por Aldo Borghes
#
# Objetivo:
#   Crear o resetear un usuario administrador de WordPress en un sitio Bitnami.
#
# Características:
#   - Detecta DB_NAME, DB_USER, DB_PASSWORD, DB_HOST y table_prefix desde wp-config.php
#   - Crea el usuario si no existe.
#   - Si existe, actualiza la contraseña y asegura que tenga rol Administrator.
#   - PRIORIDAD: usa wp-cli si está disponible (hash correcto de WP).
#   - Fallback: SQL directo (menos recomendable) si wp-cli no existe.
#
# Requisitos:
#   - Ejecutar con sudo/root en un stack Bitnami.
#   - WordPress ya instalado en /opt/bitnami/sites/<site>/htdocs
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SITE=""
ROOT="/opt/bitnami/sites"
INTERACTIVE=true

USERNAME=""
EMAIL=""
PASSWORD=""

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  sudo bash \$(basename "\$0") --site <dominio> [opciones]

Parámetros obligatorios:
  -s | --site <dominio>       Dominio (carpeta en /opt/bitnami/sites/<dominio>)

Opciones:
       --username <user>      Nombre de usuario WP (por defecto: admin-rescate)
       --email <email>        Email del usuario (por defecto: admin@<dominio>)
       --password <pass>      Contraseña del usuario (si se omite, se pedirá)
       --root <ruta>          Ruta base de sitios (por defecto /opt/bitnami/sites)
       --no-interactive       No hacer preguntas, usar solo parámetros
       --help                 Mostrar esta ayuda

Ejemplos:

  Modo interactivo:
    sudo bash \$(basename "\$0") --site example.com

  Modo no interactivo (NO recomendado pasar contraseñas por CLI):
    sudo bash \$(basename "\$0") --site example.com --no-interactive \\
         --username exampleuser --email admin@example.com \\
         --password '<TEMP_PASSWORD>'

  Nota: si puedes, usa el modo interactivo para evitar exponer la contraseña en el historial o en 'ps'.
EOF
}

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site)        SITE="$2"; shift 2;;
    --root)           ROOT="$2"; shift 2;;
    --username)       USERNAME="$2"; shift 2;;
    --email)          EMAIL="$2"; shift 2;;
    --password)       PASSWORD="$2"; shift 2;;
    --no-interactive) INTERACTIVE=false; shift;;
    -h|--help)        usage; exit 0;;
    *)                err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

# ---------- Validaciones básicas ----------
[[ $EUID -eq 0 ]] || err "Debes ejecutar este script con sudo/root."
[[ -n "$SITE" ]] || err "Debes indicar el dominio con --site <dominio>."
[[ -d /opt/bitnami/apache ]] || err "No se encontró /opt/bitnami/apache (no parece un stack Bitnami)."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/htdocs"
WPCONFIG="$DOCROOT/wp-config.php"

[[ -d "$DOCROOT" ]] || err "No existe el DocumentRoot esperado: $DOCROOT"
[[ -f "$WPCONFIG" ]] || err "No se encuentra wp-config.php en $WPCONFIG"

# ---------- Funciones para preguntas interactivas ----------
ask() {
  local prompt="$1"
  local default="$2"
  local var
  read -r -p "$prompt [$default]: " var
  echo "${var:-$default}"
}

ask_password() {
  local prompt="$1"
  local pass1 pass2
  while true; do
    read -r -s -p "$prompt: " pass1
    echo ""
    read -r -s -p "Repite la contraseña: " pass2
    echo ""
    if [[ "$pass1" != "$pass2" ]]; then
      echo "Las contraseñas no coinciden. Inténtalo de nuevo."
    elif [[ -z "$pass1" ]]; then
      echo "La contraseña no puede estar vacía."
    else
      PASSWORD="$pass1"
      break
    fi
  done
}

interactive_prompts() {
  if [[ "$INTERACTIVE" = false ]]; then
    log "Modo no interactivo: no se harán preguntas."
    return
  fi

  log "Modo interactivo: se crearán/ajustarán los datos del usuario administrador."

  local default_user="admin-rescate"
  local default_email="admin@$SITE"

  [[ -z "$USERNAME" ]] && USERNAME=$(ask "Nombre de usuario WP" "$default_user")
  [[ -z "$EMAIL"    ]] && EMAIL=$(ask "Email del usuario" "$default_email")
  [[ -z "$PASSWORD" ]] && ask_password "Introduce la contraseña para el usuario $USERNAME"

  echo ""
  echo "Resumen:"
  echo "  Usuario : $USERNAME"
  echo "  Email   : $EMAIL"
  echo "  Sitio   : $SITE"
  echo ""
  read -r -p "¿Confirmas la creación/actualización de este usuario administrador? [S/n]: " reply
  reply="${reply:-S}"
  case "${reply,,}" in
    s|si|sí|y|yes) ;;
    *) err "Operación cancelada por el usuario.";;
  esac
}

# ---------- Completar datos si falta algo en modo no interactivo ----------
if [[ "$INTERACTIVE" = false ]]; then
  [[ -z "$USERNAME" ]] && err "En modo --no-interactive debes indicar --username."
  [[ -z "$EMAIL"    ]] && err "En modo --no-interactive debes indicar --email."
  [[ -z "$PASSWORD" ]] && err "En modo --no-interactive debes indicar --password."
fi

interactive_prompts

# Validación simple de caracteres problemáticos (evitar comillas simples en user/email)
if [[ "$USERNAME" == *"'"* ]] || [[ "$EMAIL" == *"'"* ]]; then
  err "Por simplicidad, el script no permite comillas simples en usuario o email."
fi

# ---------------------------------------------------------------------------
# PRIORIDAD: usar wp-cli si existe (recomendado)
# ---------------------------------------------------------------------------
WP_CLI="/opt/bitnami/wp-cli/bin/wp"

if [[ -x "$WP_CLI" ]]; then
  log "wp-cli detectado. Gestionando usuario con wp-cli (hash correcto de WordPress)."

  # Comprobar instalación de WP
  sudo -u bitnami "$WP_CLI" --path="$DOCROOT" core is-installed >/dev/null 2>&1 \
    || err "WordPress no parece instalado en $DOCROOT"

  if sudo -u bitnami "$WP_CLI" --path="$DOCROOT" user get "$USERNAME" >/dev/null 2>&1; then
    sudo -u bitnami "$WP_CLI" --path="$DOCROOT" user update "$USERNAME" --user_pass="$PASSWORD"
    sudo -u bitnami "$WP_CLI" --path="$DOCROOT" user set-role "$USERNAME" administrator
    log "Usuario existente actualizado y rol asegurado."
  else
    sudo -u bitnami "$WP_CLI" --path="$DOCROOT" user create "$USERNAME" "$EMAIL" \
      --role=administrator --user_pass="$PASSWORD" --skip-email
    log "Usuario creado con rol administrador."
  fi

  cat <<EOF

[INFO] Usuario administrador preparado correctamente (wp-cli).

  Sitio:     $SITE
  Usuario:   $USERNAME
  Email:     $EMAIL

Login:
  http://$SITE/wp-login.php

Recuerda cambiar la contraseña desde el propio WordPress tras usar este usuario de rescate.
EOF
  exit 0
fi

warn "wp-cli no encontrado en $WP_CLI. Se usará SQL (fallback, menos recomendable)."

# ---------------------------------------------------------------------------
# FALLBACK: método SQL (si no hay wp-cli)
# ---------------------------------------------------------------------------

log "Leyendo configuración de WordPress desde $WPCONFIG (fallback SQL)."

DB_NAME=$(grep "DB_NAME" "$WPCONFIG" | sed "s/.*['\"]DB_NAME['\"][^']*'\([^']*\)'.*/\1/")
DB_USER=$(grep "DB_USER" "$WPCONFIG" | sed "s/.*['\"]DB_USER['\"][^']*'\([^']*\)'.*/\1/")
DB_PASSWORD_WP=$(grep "DB_PASSWORD" "$WPCONFIG" | sed "s/.*['\"]DB_PASSWORD['\"][^']*'\([^']*\)'.*/\1/")
DB_HOST=$(grep "DB_HOST" "$WPCONFIG" | sed "s/.*['\"]DB_HOST['\"][^']*'\([^']*\)'.*/\1/")
TABLE_PREFIX=$(grep "table_prefix" "$WPCONFIG" | sed "s/.*='\([^']*\)'.*/\1/")

[[ -n "$DB_NAME" ]] || err "No se pudo obtener DB_NAME de wp-config.php"
[[ -n "$DB_USER" ]] || err "No se pudo obtener DB_USER de wp-config.php"
[[ -n "$DB_PASSWORD_WP" ]] || err "No se pudo obtener DB_PASSWORD de wp-config.php"
[[ -n "$DB_HOST" ]] || DB_HOST="localhost"
[[ -n "$TABLE_PREFIX" ]] || TABLE_PREFIX="wp_"

DB_CLI="/opt/bitnami/mariadb/bin/mariadb"

# Escapar comillas simples en la contraseña para SQL
PASSWORD_ESCAPED=${PASSWORD//\'/\'\'}

log "Conectando a la base de datos con el usuario de WordPress (no root)."

USER_ID=$("$DB_CLI" -u"$DB_USER" -p"$DB_PASSWORD_WP" -h "$DB_HOST" -N -s \
  -e "SELECT ID FROM ${TABLE_PREFIX}users WHERE user_login='${USERNAME}'" "$DB_NAME" || true)

if [[ -z "$USER_ID" ]]; then
  log "El usuario $USERNAME no existe. Se creará un nuevo usuario admin (fallback SQL)."

  SQL_CREATE_USER="
INSERT INTO ${TABLE_PREFIX}users
  (user_login, user_pass, user_nicename, user_email, user_status)
VALUES
  ('$USERNAME', MD5('$PASSWORD_ESCAPED'), '$USERNAME', '$EMAIL', 0);
"
  "$DB_CLI" -u"$DB_USER" -p"$DB_PASSWORD_WP" -h "$DB_HOST" "$DB_NAME" -e "$SQL_CREATE_USER"

  USER_ID=$("$DB_CLI" -u"$DB_USER" -p"$DB_PASSWORD_WP" -h "$DB_HOST" -N -s \
    -e "SELECT ID FROM ${TABLE_PREFIX}users WHERE user_login='${USERNAME}'" "$DB_NAME")

  [[ -z "$USER_ID" ]] && err "No se pudo obtener el ID del usuario tras crearlo."
  log "Usuario creado con ID = $USER_ID"
else
  log "El usuario $USERNAME ya existe con ID = $USER_ID. Se actualizará la contraseña (fallback SQL)."
  SQL_UPDATE_PASS="
UPDATE ${TABLE_PREFIX}users
SET user_pass = MD5('$PASSWORD_ESCAPED')
WHERE ID = $USER_ID;
"
  "$DB_CLI" -u"$DB_USER" -p"$DB_PASSWORD_WP" -h "$DB_HOST" "$DB_NAME" -e "$SQL_UPDATE_PASS"
fi

CAP_KEY="${TABLE_PREFIX}capabilities"
LEVEL_KEY="${TABLE_PREFIX}user_level"

log "Ajustando metadatos para que el usuario tenga rol de administrador (fallback SQL)."

SQL_META="
DELETE FROM ${TABLE_PREFIX}usermeta
  WHERE user_id = $USER_ID
    AND meta_key IN ('$CAP_KEY', '$LEVEL_KEY');

INSERT INTO ${TABLE_PREFIX}usermeta (user_id, meta_key, meta_value)
VALUES
  ($USER_ID, '$CAP_KEY', 'a:1:{s:13:\"administrator\";b:1;}'),
  ($USER_ID, '$LEVEL_KEY', '10');
"
"$DB_CLI" -u"$DB_USER" -p"$DB_PASSWORD_WP" -h "$DB_HOST" "$DB_NAME" -e "$SQL_META"

cat <<EOF

[INFO] Usuario administrador preparado correctamente (fallback SQL).

  Sitio:          $SITE
  Usuario:        $USERNAME
  Email:          $EMAIL
  ID en BD:       $USER_ID

Login:
  http://$SITE/wp-login.php

Recuerda cambiar la contraseña desde el propio WordPress tras usar este usuario de rescate.

AVISO:
  Este modo SQL usa MD5 como compatibilidad legacy. Lo recomendable es instalar/usar wp-cli.
EOF
