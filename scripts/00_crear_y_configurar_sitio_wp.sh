#!/usr/bin/env bash
# Script unificado Fase 1 + Fase 2 + ajuste wp-config.php
#Desarrollado por Aldo Borghes

set -Eeuo pipefail

SITE=""
ROOT="/opt/bitnami/sites"
FASE2_ARGS=()

log()  { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site)
      SITE="$2"
      FASE2_ARGS+=("$1" "$2")
      shift 2
      ;;
    --root)
      ROOT="$2"
      FASE2_ARGS+=("$1" "$2")
      shift 2
      ;;
    *)
      FASE2_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ -n "$SITE" ]] || err "Debes indicar --site <dominio>."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/htdocs"
WPCONFIG="$DOCROOT/wp-config.php"

F1_SCRIPT="/opt/scripts/wp-migracion/01_crear_sitio.sh"
F2_SCRIPT="/opt/scripts/wp-migracion/02_configurar_wordpress.sh"

log "FASE 1"
bash "$F1_SCRIPT" --site "$SITE" --root "$ROOT"
sleep 5

log "FASE 2"
bash "$F2_SCRIPT" "${FASE2_ARGS[@]}"
sleep 3

log "Ajustando wp-config.php"
if [[ -f "$WPCONFIG" ]]; then
cat <<EOF >> "$WPCONFIG"

define('FS_METHOD', 'direct');
define('FS_CHMOD_DIR', 0775);
define('FS_CHMOD_FILE', 0664);
EOF
fi

log "Completado."
