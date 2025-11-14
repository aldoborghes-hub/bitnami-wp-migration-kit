#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: script_fase3_post_wp.sh
#
# Objetivo (Fase 3):
#   - Emitir o renovar certificado Let's Encrypt para un sitio Bitnami.
#   - Crear el VirtualHost HTTPS para el dominio usando lego.
#   - Probar la configuración de Apache y reiniciar el servicio.
#
#   * NO toca la base de datos de WordPress (siteurl/home).
#   * NO fuerza redirección HTTP→HTTPS automáticamente (se explica en la ayuda).
#
# Uso (ejemplos):
#   sudo bash script_fase3_post_wp.sh --site vendeenchina.es \
#        --alias www.vendeenchina.es \
#        --email admin@vendeenchina.es
#
# Parámetros:
#   -s | --site <dominio>       Dominio principal (carpeta en /opt/bitnami/sites/<dominio>)
#   -a | --alias <alias>        Alias adicional (ej: www.dominio.com). Repetible.
#        --root <ruta>          Ruta base (por defecto /opt/bitnami/sites)
#        --email <correo>       Correo para Let's Encrypt (obligatorio)
#        --lego-bin <ruta>      Ruta binario lego (por defecto /opt/bitnami/letsencrypt/lego)
#        --lego-path <ruta>     Ruta datos lego (por defecto /opt/bitnami/letsencrypt)
#        --help                 Mostrar ayuda
#
# Requisitos:
#   - Ejecutar con sudo/root.
#   - Stack Bitnami en /opt/bitnami.
#   - DNS del dominio apuntando a la instancia.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SITE=""
ALIASES=()
ROOT="/opt/bitnami/sites"
EMAIL=""
LEGO_BIN="/opt/bitnami/letsencrypt/lego"
LEGO_PATH="/opt/bitnami/letsencrypt"
VHOSTS_DIR="/opt/bitnami/apache/conf/vhosts"

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  sudo bash \$(basename "\$0") --site <dominio> --email <correo> [opciones]

Parámetros:
  -s | --site <dominio>     Dominio principal (carpeta en /opt/bitnami/sites/<dominio>)
  -a | --alias <alias>      Alias adicional (ej: www.dominio.com). Repetible.
       --root <ruta>        Ruta base (por defecto /opt/bitnami/sites)
       --email <correo>     Correo para Let's Encrypt (obligatorio)
       --lego-bin <ruta>    Ruta binario lego (por defecto /opt/bitnami/letsencrypt/lego)
       --lego-path <ruta>   Ruta datos lego (por defecto /opt/bitnami/letsencrypt)
       --help               Mostrar ayuda

Ejemplos:
  sudo bash \$(basename "\$0") --site vendeenchina.es --alias www.vendeenchina.es \
       --email admin@vendeenchina.es
EOF
}

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site)     SITE="$2"; shift 2;;
    -a|--alias)    ALIASES+=("$2"); shift 2;;
    --root)        ROOT="$2"; shift 2;;
    --email)       EMAIL="$2"; shift 2;;
    --lego-bin)    LEGO_BIN="$2"; shift 2;;
    --lego-path)   LEGO_PATH="$2"; shift 2;;
    -h|--help)     usage; exit 0;;
    *)             err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

# ---------- Validaciones ----------
[[ $EUID -eq 0 ]] || err "Debes ejecutar este script con sudo/root."
[[ -n "$SITE" ]] || err "Debes indicar el dominio con --site <dominio>."
[[ -n "$EMAIL" ]] || err "Debes indicar un correo con --email <correo>."
[[ -d /opt/bitnami/apache ]] || err "No se encontró /opt/bitnami/apache (no parece un stack Bitnami)."
[[ -x "$LEGO_BIN" ]] || err "No se encuentra lego en $LEGO_BIN (o no es ejecutable)."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/htdocs"
HTTPS_VHOST="$VHOSTS_DIR/${SITE}-https-vhost.conf"

[[ -d "$DOCROOT" ]] || err "No existe el DocumentRoot esperado: $DOCROOT"

CERT_DIR="$LEGO_PATH/certificates"
CERT_FILE="$CERT_DIR/${SITE}.crt"
KEY_FILE="$CERT_DIR/${SITE}.key"
CHAIN_FILE="$CERT_DIR/${SITE}.issuer.crt"

# ---------- Funciones ----------

issue_or_renew_cert() {
  log "Emitiendo o renovando certificado Let's Encrypt con lego"
  mkdir -p "$LEGO_PATH"

  local args=(
    "--email=$EMAIL"
    "--domains=$SITE"
    "--path=$LEGO_PATH"
  )

  if [[ ${#ALIASES[@]} -gt 0 ]]; then
    for a in "${ALIASES[@]}"; do
      args+=("--domains=$a")
    done
  fi

  local action="run"
  if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
    action="renew"
    log "Certificado existente detectado. Se intentará renovar (acción: renew)."
  else
    log "No se encontró certificado previo. Se emitirá uno nuevo (acción: run)."
  fi

  "$LEGO_BIN" "${args[@]}" "$action"
  log "lego $action completado."
}

create_https_vhost() {
  log "Creando VirtualHost HTTPS en $HTTPS_VHOST"

  mkdir -p "$VHOSTS_DIR"

  if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
    warn "No se han encontrado CERT/KEY tras ejecutar lego. Esperado:"
    warn "  $CERT_FILE"
    warn "  $KEY_FILE"
    warn "Revisa la salida de lego antes de continuar."
  fi

  {
    echo "<VirtualHost *:443>"
    echo "  ServerName $SITE"
    if [[ ${#ALIASES[@]} -gt 0 ]]; then
      echo -n "  ServerAlias"
      for a in "${ALIASES[@]}"; do
        echo -n " $a"
      done
      echo
    fi
    echo
    echo "  DocumentRoot \"$DOCROOT\""
    echo
    echo "  SSLEngine on"
    echo "  SSLCertificateFile \"$CERT_FILE\""
    echo "  SSLCertificateKeyFile \"$KEY_FILE\""
    if [[ -f "$CHAIN_FILE" ]]; then
      echo "  SSLCertificateChainFile \"$CHAIN_FILE\""
    fi
    echo
    echo "  <Directory \"$DOCROOT\">"
    echo "    Options FollowSymLinks"
    echo "    AllowOverride All"
    echo "    Require all granted"
    echo "  </Directory>"
    echo "</VirtualHost>"
  } > "$HTTPS_VHOST"

  chown bitnami:daemon "$HTTPS_VHOST"
  chmod 644 "$HTTPS_VHOST"

  log "VirtualHost HTTPS creado en: $HTTPS_VHOST"
}

apache_test_restart() {
  log "Validando sintaxis de Apache..."
  /opt/bitnami/apache/bin/apachectl -t
  log "Reiniciando Apache..."
  /opt/bitnami/ctlscript.sh restart apache
}

summary() {
  cat <<EOF

[INFO] Fase 3 completada para el sitio: $SITE

 - Sitio base:          $SITEDIR
 - DocumentRoot:        $DOCROOT
 - Certificado CRT:     $CERT_FILE
 - Clave privada KEY:   $KEY_FILE
 - Cadena (issuer):     $CHAIN_FILE (si existe)
 - VHost HTTPS:         $HTTPS_VHOST

Acciones realizadas:
 - Emisión/renovación de certificado Let's Encrypt con lego.
 - Creación/actualización de VirtualHost HTTPS para el dominio.
 - Validación de configuración Apache y reinicio del servicio.

Tareas siguientes recomendadas:
 1) Verificar acceso por HTTPS en el navegador:
      https://$SITE/
      https://$SITE/wp-login.php

 2) En WordPress (cuando todo funcione por HTTPS):
      - Ajustar en Ajustes → Generales:
          * Dirección de WordPress (URL): https://$SITE
          * Dirección del sitio (URL):    https://$SITE
      - Guardar cambios.

 3) (Opcional) Forzar redirección HTTP→HTTPS
      Editar el VirtualHost HTTP en:
        /opt/bitnami/apache/conf/vhosts/${SITE}-vhost.conf

      Y añadir dentro del bloque <VirtualHost *:80>:
        RewriteEngine On
        RewriteCond %{HTTPS} !=on
        RewriteRule ^/(.*) https://%{SERVER_NAME}/\$1 [R=301,L]

      Después, reiniciar Apache:
        sudo /opt/bitnami/ctlscript.sh restart apache
EOF
}

# ---------- Ejecución ----------
log "Iniciando Fase 3 para el sitio: $SITE"

issue_or_renew_cert
create_https_vhost
apache_test_restart
summary

log "Fase 3 finalizada."
