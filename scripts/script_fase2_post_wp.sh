#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: script_fase2_post_wp.sh
# Objetivo:
#   Ajustes posteriores a la creación de un sitio WordPress en Bitnami:
#   - Permisos y propietarios correctos (bitnami:daemon)
#   - Forzar FS_METHOD=direct en wp-config.php
#   - (Opcional) Actualizar límites de PHP (upload_max_filesize, post_max_size,
#     memory_limit, max_execution_time, max_input_time)
#   - (Opcional) Ajustar AI1WM_MAX_FILE_SIZE del plugin All-in-One WP Migration
#
# Uso (ejemplos):
#   sudo bash script_fase2_post_wp.sh --site vendeenchina.es
#
#   sudo bash script_fase2_post_wp.sh --site vendeenchina.es \
#        --php-upload-mb 2048 --php-memory-mb 1024 --php-tune
#
#   sudo bash script_fase2_post_wp.sh --site vendeenchina.es \
#        --ai1wm-bytes 2147483648
#
# Parámetros:
#   -s | --site <dominio>       Dominio (carpeta en /opt/bitnami/sites/<dominio>)
#        --root <ruta>          Ruta base (por defecto /opt/bitnami/sites)
#        --php-tune             Aplicar cambios en php.ini
#        --php-upload-mb <MB>   upload_max_filesize y post_max_size (MB)
#        --php-memory-mb <MB>   memory_limit (MB)
#        --php-max-exec <seg>   max_execution_time
#        --php-max-input <seg>  max_input_time
#        --ai1wm-bytes <bytes>  Nuevo valor para AI1WM_MAX_FILE_SIZE
#        --help                 Mostrar ayuda
#
# Requisitos:
#   - Ejecutar con sudo/root.
#   - Stack Bitnami en /opt/bitnami.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SITE=""
ROOT="/opt/bitnami/sites"
PHP_INI="/opt/bitnami/php/etc/php.ini"
TUNE_PHP=false
PHP_UPLOAD_MB=0
PHP_MEMORY_MB=0
PHP_MAX_EXEC=0
PHP_MAX_INPUT=0
AI1WM_BYTES=0

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  sudo bash \$(basename "\$0") --site <dominio> [opciones]

Parámetros:
  -s | --site <dominio>       Dominio (carpeta en /opt/bitnami/sites/<dominio>)
       --root <ruta>          Ruta base (por defecto /opt/bitnami/sites)

       --php-tune             Aplicar cambios en php.ini
       --php-upload-mb <MB>   upload_max_filesize y post_max_size (MB)
       --php-memory-mb <MB>   memory_limit (MB)
       --php-max-exec <seg>   max_execution_time
       --php-max-input <seg>  max_input_time

       --ai1wm-bytes <bytes>  Nuevo valor para AI1WM_MAX_FILE_SIZE
       --help                 Mostrar ayuda

Ejemplos:
  sudo bash \$(basename "\$0") --site vendeenchina.es
  sudo bash \$(basename "\$0") --site vendeenchina.es --php-tune --php-upload-mb 2048 --php-memory-mb 1024
  sudo bash \$(basename "\$0") --site vendeenchina.es --ai1wm-bytes 2147483648
EOF
}

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site)        SITE="$2"; shift 2;;
    --root)           ROOT="$2"; shift 2;;
    --php-tune)       TUNE_PHP=true; shift;;
    --php-upload-mb)  PHP_UPLOAD_MB="$2"; shift 2;;
    --php-memory-mb)  PHP_MEMORY_MB="$2"; shift 2;;
    --php-max-exec)   PHP_MAX_EXEC="$2"; shift 2;;
    --php-max-input)  PHP_MAX_INPUT="$2"; shift 2;;
    --ai1wm-bytes)    AI1WM_BYTES="$2"; shift 2;;
    -h|--help)        usage; exit 0;;
    *)                err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

# ---------- Validaciones ----------
[[ $EUID -eq 0 ]] || err "Debes ejecutar este script con sudo/root."
[[ -n "$SITE" ]] || err "Debes indicar el dominio con --site <dominio>."
[[ -d /opt/bitnami/apache ]] || err "No se encontró /opt/bitnami/apache (no parece un stack Bitnami)."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/htdocs"
WPCONFIG="$DOCROOT/wp-config.php"
AI1WM_CONSTANTS="$DOCROOT/wp-content/plugins/all-in-one-wp-migration/constants.php"

[[ -d "$DOCROOT" ]] || err "No existe el DocumentRoot esperado: $DOCROOT"
[[ -f "$WPCONFIG" ]] || warn "No se ha encontrado wp-config.php en $WPCONFIG (¿WordPress instalado?). Continuaré, pero se omitirá FS_METHOD."

# ---------- Funciones ----------

fix_permissions() {
  log "Ajustando propietarios y permisos en $SITEDIR"

  chown -R bitnami:daemon "$SITEDIR"

  find "$SITEDIR" -type d -exec chmod 775 {} \;
  find "$SITEDIR" -type f -exec chmod 664 {} \;

  if [[ -d "$DOCROOT/wp-content" ]]; then
    log "Ajustando permisos reforzados para wp-content"
    chown -R bitnami:daemon "$DOCROOT/wp-content"
    chmod -R 775 "$DOCROOT/wp-content"
  fi

  log "Permisos aplicados."
}

ensure_fs_method_direct() {
  if [[ ! -f "$WPCONFIG" ]]; then
    warn "No se puede ajustar FS_METHOD porque no existe $WPCONFIG"
    return
  fi

  log "Asegurando FS_METHOD=direct en wp-config.php"
  if grep -q "FS_METHOD" "$WPCONFIG"; then
    sed -i "s/define(\s*'FS_METHOD'.*/define('FS_METHOD', 'direct');/" "$WPCONFIG"
  else
    # Insertar justo antes de la línea de fin de edición
    if grep -q "Happy publishing" "$WPCONFIG"; then
      sed -i "/Happy publishing/i define('FS_METHOD', 'direct');\ndefine('FS_CHMOD_DIR', 0775);\ndefine('FS_CHMOD_FILE', 0664);\n" "$WPCONFIG"
    else
      cat <<EOF >> "$WPCONFIG"

define('FS_METHOD', 'direct');
define('FS_CHMOD_DIR', 0775);
define('FS_CHMOD_FILE', 0664);
EOF
    fi
  fi
  log "FS_METHOD=direct configurado."
}

tune_php_ini() {
  if [[ "$TUNE_PHP" = false ]]; then
    log "No se ha solicitado ajuste de php.ini (--php-tune no presente)."
    return
  fi

  [[ -f "$PHP_INI" ]] || err "No se encuentra php.ini en $PHP_INI"

  log "Aplicando cambios en php.ini"

  if (( PHP_UPLOAD_MB > 0 )); then
    log " - upload_max_filesize = ${PHP_UPLOAD_MB}M"
    log " - post_max_size      = ${PHP_UPLOAD_MB}M"
    sed -i "s/^upload_max_filesize = .*/upload_max_filesize = ${PHP_UPLOAD_MB}M/" "$PHP_INI"
    sed -i "s/^post_max_size = .*/post_max_size = ${PHP_UPLOAD_MB}M/" "$PHP_INI"
  fi

  if (( PHP_MEMORY_MB > 0 )); then
    log " - memory_limit = ${PHP_MEMORY_MB}M"
    sed -i "s/^memory_limit = .*/memory_limit = ${PHP_MEMORY_MB}M/" "$PHP_INI"
  fi

  if (( PHP_MAX_EXEC > 0 )); then
    log " - max_execution_time = ${PHP_MAX_EXEC}"
    sed -i "s/^max_execution_time = .*/max_execution_time = ${PHP_MAX_EXEC}/" "$PHP_INI"
  fi

  if (( PHP_MAX_INPUT > 0 )); then
    log " - max_input_time = ${PHP_MAX_INPUT}"
    sed -i "s/^max_input_time = .*/max_input_time = ${PHP_MAX_INPUT}/" "$PHP_INI"
  fi

  log "Reiniciando php-fpm tras cambios en php.ini"
  /opt/bitnami/ctlscript.sh restart php-fpm
}

update_ai1wm_limit() {
  if (( AI1WM_BYTES <= 0 )); then
    log "No se ha solicitado cambio de AI1WM_MAX_FILE_SIZE (sin --ai1wm-bytes)."
    return
  fi

  if [[ ! -f "$AI1WM_CONSTANTS" ]]; then
    warn "No se encuentra el plugin All-in-One WP Migration en $AI1WM_CONSTANTS"
    return
  fi

  log "Actualizando AI1WM_MAX_FILE_SIZE a $AI1WM_BYTES bytes"
  if grep -q "AI1WM_MAX_FILE_SIZE" "$AI1WM_CONSTANTS"; then
    sed -i "s/define( 'AI1WM_MAX_FILE_SIZE'.*/define( 'AI1WM_MAX_FILE_SIZE', ${AI1WM_BYTES} );/" "$AI1WM_CONSTANTS"
  else
    cat <<EOF >> "$AI1WM_CONSTANTS"

define( 'AI1WM_MAX_FILE_SIZE', ${AI1WM_BYTES} );
EOF
  fi
}

summary() {
  cat <<EOF

[INFO] Fase 2 completada para el sitio: $SITE

 - Ruta sitio:      $SITEDIR
 - DocumentRoot:    $DOCROOT
 - wp-config.php:   $WPCONFIG
 - php.ini:         $PHP_INI
 - AI1WM constants: $AI1WM_CONSTANTS

Acciones realizadas:
 - Permisos y propietarios ajustados (bitnami:daemon, 775/664).
 - FS_METHOD=direct asegurado en wp-config.php (si existía).
$( [[ "$TUNE_PHP" = true ]] && echo " - php.ini modificado con los parámetros indicados." || echo " - php.ini no modificado (no se pasó --php-tune)." )
$( (( AI1WM_BYTES > 0 )) && echo " - AI1WM_MAX_FILE_SIZE ajustado a ${AI1WM_BYTES} bytes (si el plugin existe)." || echo " - AI1WM_MAX_FILE_SIZE no modificado." )

Siguientes pasos recomendados:
 - Entrar al panel de WordPress:
     http://$SITE/wp-admin/
 - Instalar o verificar el plugin All-in-One WP Migration.
 - Realizar la importación del backup.
 - Una vez migrado y probado en HTTP, proceder con la fase de HTTPS (Let’s Encrypt).
EOF
}

# ---------- Ejecución ----------
log "Iniciando Fase 2 para el sitio: $SITE"

fix_permissions
ensure_fs_method_direct
tune_php_ini
update_ai1wm_limit
summary

log "Fase 2 finalizada."
