#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: script_fase1_sitio_bitnami.sh
# Objetivo:
#   Crear la estructura base de un sitio WordPress bajo /opt/bitnami/sites/<dominio>
#   + generar VirtualHost Apache + (opcional) instalar WordPress limpio.
#
# Uso (ejemplos):
#   sudo bash script_fase1_sitio_bitnami.sh --site vendeenchina.es --alias www.vendeenchina.es
#   sudo bash script_fase1_sitio_bitnami.sh -s midominio.com --no-wp
#
# Flags:
#   -s | --site <dominio>      Dominio principal (obligatorio)
#   -a | --alias <alias>       Alias adicional (www.dominio.com). Repetible.
#        --no-wp               No instalar WordPress (solo index de prueba)
#        --force               Reemplazar vhost.conf si ya existe
#        --root <ruta>         Ruta base (por defecto /opt/bitnami/sites)
#        --docroot <subdir>    Subcarpeta para DocumentRoot (por defecto htdocs)
#        --apache-inc <fich>   Fichero donde añadir el Include (default httpd.conf)
#        --help                Mostrar ayuda
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SITE=""
ALIASES=()
ROOT="/opt/bitnami/sites"
DOCROOT_SUBDIR="htdocs"
APACHE_INCLUDE_FILE="/opt/bitnami/apache/conf/httpd.conf"
NO_WP=false
FORCE=false

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site) SITE="$2"; shift 2;;
    -a|--alias) ALIASES+=("$2"); shift 2;;
    --no-wp) NO_WP=true; shift;;
    --force) FORCE=true; shift;;
    --root) ROOT="$2"; shift 2;;
    --docroot) DOCROOT_SUBDIR="$2"; shift 2;;
    --apache-inc) APACHE_INCLUDE_FILE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

# ---------- Validaciones ----------
[[ $EUID -eq 0 ]] || err "Debes ejecutar este script con sudo/root."
[[ -n "$SITE" ]] || err "Debes indicar el dominio con --site <dominio>."
[[ -d /opt/bitnami/apache ]] || err "No se encontró /opt/bitnami/apache (no parece un stack Bitnami)."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/$DOCROOT_SUBDIR"
CONFDIR="$SITEDIR/conf"
LOGDIR="$SITEDIR/logs"
VHOST_FILE="$CONFDIR/vhost.conf"

# ---------- Funciones ----------
ensure_include() {
  local inc_line='Include "/opt/bitnami/sites/*/conf/*.conf"'
  if ! grep -qF "$inc_line" "$APACHE_INCLUDE_FILE"; then
    log "Añadiendo Include de sitios personalizados a $APACHE_INCLUDE_FILE"
    echo "$inc_line" >> "$APACHE_INCLUDE_FILE"
  else
    log "Include de /opt/bitnami/sites ya presente en $APACHE_INCLUDE_FILE"
  fi
}

create_structure() {
  log "Creando estructura de directorios en $SITEDIR"
  mkdir -p "$DOCROOT" "$CONFDIR" "$LOGDIR"
  chown -R bitnami:daemon "$SITEDIR"
  find "$SITEDIR" -type d -exec chmod 755 {} +
  find "$SITEDIR" -type f -exec chmod 644 {} + || true
}

create_vhost() {
  if [[ -f "$VHOST_FILE" && "$FORCE" = false ]]; then
    warn "Ya existe $VHOST_FILE (usa --force para sobreescribir)."
    return
  fi

  log "Generando VirtualHost en $VHOST_FILE"
  local server_aliases=""
  for a in "${ALIASES[@]:-}"; do
    [[ -n "$a" ]] && server_aliases+="\n  ServerAlias $a"
  done

  cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
  ServerName $SITE${server_aliases}
  DocumentRoot "$DOCROOT"

  <Directory "$DOCROOT">
    AllowOverride All
    Require all granted
    Options -Indexes +FollowSymLinks
  </Directory>

  ErrorLog  "$LOGDIR/error.log"
  CustomLog "$LOGDIR/access.log" combined
</VirtualHost>
EOF
}

install_wordpress() {
  if [[ "$NO_WP" = true ]]; then
    log "Opción --no-wp activa: creando index de prueba"
    echo "$SITE OK - $(date)" > "$DOCROOT/index.html"
    chown bitnami:daemon "$DOCROOT/index.html"
    chmod 644 "$DOCROOT/index.html"
    return
  fi

  log "Instalando WordPress limpio en $DOCROOT"
  pushd "$DOCROOT" >/dev/null
  rm -f index.html || true
  curl -fsSL https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz
  tar -xzf /tmp/wordpress.tar.gz --strip-components=1
  rm -f /tmp/wordpress.tar.gz
  chown -R bitnami:daemon "$DOCROOT"
  popd >/dev/null
}

apache_test_restart() {
  log "Validando sintaxis de Apache..."
  /opt/bitnami/apache/bin/apachectl -t
  log "Reiniciando Apache..."
  /opt/bitnami/ctlscript.sh restart apache
}

show_summary() {
  cat <<EOF

[INFO] Sitio preparado:

  Dominio:      $SITE
  Ruta base:    $SITEDIR
  DocumentRoot: $DOCROOT
  VHost:        $VHOST_FILE

Siguiente paso:

  1) Añadir entrada temporal en /etc/hosts de tu PC, por ejemplo:
       IP_DEL_SERVIDOR   $SITE   www.$SITE

  2) Abrir en el navegador:
       http://$SITE/wp-admin

  3) Completar la instalación de WordPress o importar el backup.

EOF
}

# ---------- Ejecución ----------
log "Iniciando Fase 1 para el sitio: $SITE"
ensure_include
create_structure
create_vhost
install_wordpress
apache_test_restart
show_summary
log "Fase 1 completada."
