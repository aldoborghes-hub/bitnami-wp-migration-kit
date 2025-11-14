#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: script_fase2_post_wp.sh
# Objetivo:
#   Ajustes estándar tras instalar o migrar un WordPress:
#   - Actualizar home/siteurl
#   - Configurar enlaces permanentes /%postname%/
#   - Hacer flush de las reglas de rewrite
#
# Uso:
#   bash script_fase2_post_wp.sh --site vendeenchina.es [--docroot htdocs]
#
# Notas:
#   - Ejecutar como usuario bitnami (SIN sudo):
#       su - bitnami
#       bash script_fase2_post_wp.sh --site vendeenchina.es
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SITE=""
DOCROOT_SUBDIR="htdocs"
WP_CLI="/opt/bitnami/wp-cli/bin/wp"

log()  { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site) SITE="$2"; shift 2;;
    --docroot) DOCROOT_SUBDIR="$2"; shift 2;;
    -h|--help)
      sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

[[ -n "$SITE" ]] || err "Debes indicar --site <dominio>."
[[ -x "$WP_CLI" ]] || err "No se encuentra wp-cli en $WP_CLI"

SITEDIR="/opt/bitnami/sites/$SITE"
WP_PATH="$SITEDIR/$DOCROOT_SUBDIR"
URL="http://$SITE"

[[ -d "$WP_PATH" ]] || err "No existe el directorio $WP_PATH"

log "Usando WordPress en: $WP_PATH"
log "URL objetivo: $URL"

# Comprobar instalación
$WP_CLI --path="$WP_PATH" core is-installed || err "Parece que WordPress no está instalado todavía."

# Ajustar home y siteurl
log "Actualizando opciones home y siteurl..."
$WP_CLI --path="$WP_PATH" option update home    "$URL"
$WP_CLI --path="$WP_PATH" option update siteurl "$URL"

# Enlaces permanentes
log "Configurando enlaces permanentes /%postname%/ ..."
$WP_CLI --path="$WP_PATH" rewrite structure '/%postname%/' --hard
$WP_CLI --path="$WP_PATH" rewrite flush --hard

# Resumen
log "Valores actuales:"
$WP_CLI --path="$WP_PATH" option get home
$WP_CLI --path="$WP_PATH" option get siteurl

echo
log "Fase 2 completada para $SITE."
echo "Ahora prueba en el navegador:"
echo "  $URL"
echo "y revisa que las URLs funcionen correctamente."
