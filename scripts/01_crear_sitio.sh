#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: 01_crear_sitio.sh.sh
#Desarrollado por Aldo Borghes
# Fase 1:
#   - Crear estructura de sitio para un dominio en Bitnami:
#       /opt/bitnami/sites/<dominio>/
#         ├── htdocs   (DocumentRoot de Apache)
#         ├── logs     (logs específicos del sitio)
#         └── conf     (config adicional incluida desde httpd.conf)
#
#   - Crear VirtualHost HTTP en:
#       /opt/bitnami/apache/conf/vhosts/<dominio>-vhost.conf
#
#   - Crear un placeholder en conf/ para evitar errores del tipo:
#       "No matches for the wildcard '*.conf' in '/opt/bitnami/sites/<dominio>/conf'"
#
# Uso:
#   sudo bash 01_crear_sitio.sh.sh --site traduccioneschino.es
#
# Requisitos:
#   - Ejecutar con sudo/root.
#   - Stack Bitnami en /opt/bitnami.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SITE=""
ROOT="/opt/bitnami/sites"
VHOSTS_DIR="/opt/bitnami/apache/conf/vhosts"

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  sudo bash \$(basename "\$0") --site <dominio> [opciones]

Parámetros:
  -s | --site <dominio>   Dominio del sitio (ej: traduccioneschino.es)
       --root <ruta>      Ruta base de sitios (por defecto /opt/bitnami/sites)
       --help             Mostrar esta ayuda

Ejemplo:
  sudo bash \$(basename "\$0") --site traduccioneschino.es
EOF
}

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site) SITE="$2"; shift 2;;
    --root)    ROOT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *)         err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

# ---------- Validaciones ----------
[[ $EUID -eq 0 ]] || err "Debes ejecutar este script con sudo/root."
[[ -n "$SITE" ]] || err "Debes indicar el dominio con --site <dominio>."
[[ -d /opt/bitnami/apache ]] || err "No se encontró /opt/bitnami/apache (no parece un stack Bitnami)."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/htdocs"
LOGDIR="$SITEDIR/logs"
CONFDIR="$SITEDIR/conf"
PLACEHOLDER_CONF="$CONFDIR/placeholder.conf"
HTTP_VHOST="$VHOSTS_DIR/${SITE}-vhost.conf"

# ---------- Creación de estructura ----------
log "Creando estructura de sitio para $SITE"

mkdir -p "$DOCROOT"
mkdir -p "$LOGDIR"
mkdir -p "$CONFDIR"

# Propietarios y permisos básicos
chown -R bitnami:daemon "$SITEDIR"
find "$SITEDIR" -type d -exec chmod 775 {} \;
find "$SITEDIR" -type f -exec chmod 664 {} \;

log "Estructura creada en: $SITEDIR"
log "  - DocumentRoot: $DOCROOT"
log "  - Logs:         $LOGDIR"
log "  - Conf:         $CONFDIR"

# ---------- Placeholder en conf/ ----------
if [[ ! -f "$PLACEHOLDER_CONF" ]]; then
  log "Creando placeholder.conf en $CONFDIR para evitar errores de IncludeOptional"
  cat > "$PLACEHOLDER_CONF" <<EOF
# placeholder.conf
# Fichero de relleno para evitar errores de Apache cuando incluye:
#   $CONFDIR/*.conf
#
# Puedes añadir aquí configuraciones específicas del sitio si lo necesitas.
EOF
  chown bitnami:daemon "$PLACEHOLDER_CONF"
  chmod 644 "$PLACEHOLDER_CONF"
else
  log "Ya existe $PLACEHOLDER_CONF, no se modifica."
fi

# ---------- Creación VirtualHost HTTP ----------
log "Creando VirtualHost HTTP en $HTTP_VHOST"

mkdir -p "$VHOSTS_DIR"

if [[ -f "$HTTP_VHOST" ]]; then
  warn "El VirtualHost $HTTP_VHOST ya existe. Se sobrescribirá."
fi

cat > "$HTTP_VHOST" <<EOF
<VirtualHost *:80>
  ServerName $SITE

  DocumentRoot "$DOCROOT"

  ErrorLog  "$LOGDIR/error.log"
  CustomLog "$LOGDIR/access.log" combined

  <Directory "$DOCROOT">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF

chown bitnami:daemon "$HTTP_VHOST"
chmod 644 "$HTTP_VHOST"

log "VirtualHost HTTP creado/actualizado."

# ---------- Probar configuración y reiniciar Apache ----------
log "Validando sintaxis de Apache..."
if ! /opt/bitnami/apache/bin/apachectl -t; then
  err "Error de sintaxis en la configuración de Apache. Revisa los mensajes anteriores."
fi

log "Reiniciando Apache..."
/opt/bitnami/ctlscript.sh restart apache

# ---------- Resumen ----------
cat <<EOF

[INFO] Fase 1 completada para el sitio: $SITE

 - Sitio base:    $SITEDIR
 - DocumentRoot:  $DOCROOT
 - Logs:          $LOGDIR
 - Conf:          $CONFDIR
 - VHost HTTP:    $HTTP_VHOST
 - Placeholder:   $PLACEHOLDER_CONF

Siguientes pasos recomendados:
  1) Instalar/copiar WordPress en:
       $DOCROOT

  2) Ejecutar Fase 2 (ajustes WordPress, permisos, php.ini, AI1WM, etc.):
       sudo bash 02_configurar_wordpress.sh.sh --site $SITE ...

  3) Entrar al panel de WordPress (una vez instalado) y realizar la migración
     con el plugin (All-in-One WP Migration
