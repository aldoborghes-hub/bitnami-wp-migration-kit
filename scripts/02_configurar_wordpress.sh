#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#Desarrollado por Aldo Borghes
# Script: script_fase2_post_wp.sh
# Objetivo:
#   Ajustes posteriores a la creación de un sitio WordPress en Bitnami:
#   - (Opcional) Descargar e instalar WordPress en htdocs si está vacío.
#   - (Opcional) Crear base de datos y usuario para WordPress.
#   - Permisos y propietarios correctos (bitnami:daemon)
#   - Forzar FS_METHOD=direct en wp-config.php
#   - (Opcional) Actualizar límites de PHP (upload_max_filesize, post_max_size,
#     memory_limit, max_execution_time, max_input_time)
#   - (Opcional) Ajustar AI1WM_MAX_FILE_SIZE del plugin All-in-One WP Migration
#
# Uso típico (modo interactivo por defecto):
#   sudo bash script_fase2_post_wp.sh --site traduccioneschino.es
#
# Uso no interactivo (todo por parámetros):
#   sudo bash script_fase2_post_wp.sh --site vendeenchina.es --no-interactive \
#        --install-wp \
#        --create-db --db-name wp_vende --db-user wp_vende --db-pass 'XXXX' \
#        --mysql-admin-user root --mysql-admin-pass 'ROOTPASS' \
#        --php-tune --php-upload-mb 2048 --php-memory-mb 1024 \
#        --php-max-exec 300 --php-max-input 300 \
#        --ai1wm-bytes 2147483648
#
# Parámetros:
#   -s | --site <dominio>       Dominio (carpeta en /opt/bitnami/sites/<dominio>)
#        --root <ruta>          Ruta base (por defecto /opt/bitnami/sites)
#
#        --install-wp           Descargar e instalar WordPress en htdocs
#
#        --create-db            Crear BD y usuario para WordPress
#        --db-name <nombre>     Nombre de la BD de WordPress
#        --db-user <usuario>    Usuario de BD para WordPress
#        --db-pass <pass>       Contraseña del usuario de BD
#        --db-host <host>       Host de BD (por defecto localhost)
#        --mysql-admin-user <u> Usuario administrador MySQL (por defecto root)
#        --mysql-admin-pass <p> Contraseña del admin MySQL
#
#        --php-tune             Aplicar cambios en php.ini
#        --php-upload-mb <MB>   upload_max_filesize y post_max_size (MB)
#        --php-memory-mb <MB>   memory_limit (MB)
#        --php-max-exec <seg>   max_execution_time
#        --php-max-input <seg>  max_input_time
#
#        --ai1wm-bytes <bytes>  Nuevo valor para AI1WM_MAX_FILE_SIZE
#
#        --no-interactive       Desactiva preguntas interactivas
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

INSTALL_WP=false

CREATE_DB=false
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST="localhost"
MYSQL_ADMIN_USER="root"
MYSQL_ADMIN_PASS=""

INTERACTIVE=true

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  sudo bash \$(basename "\$0") --site <dominio> [opciones]

Parámetros obligatorios:
  -s | --site <dominio>       Dominio (carpeta en /opt/bitnami/sites/<dominio>)

Opciones generales:
       --root <ruta>          Ruta base (por defecto /opt/bitnami/sites)
       --no-interactive       Desactiva las preguntas interactivas
       --help                 Mostrar esta ayuda

Opciones WordPress:
       --install-wp           Descargar e instalar WordPress en htdocs
       --create-db            Crear BD y usuario para WordPress
       --db-name <nombre>     Nombre de la BD de WordPress
       --db-user <usuario>    Usuario de BD para WordPress
       --db-pass <pass>       Contraseña del usuario de BD
       --db-host <host>       Host de BD (por defecto localhost)
       --mysql-admin-user <u> Usuario administrador MySQL (por defecto root)
       --mysql-admin-pass <p> Contraseña del admin MySQL

Opciones PHP:
       --php-tune             Aplicar cambios en php.ini
       --php-upload-mb <MB>   upload_max_filesize y post_max_size (MB)
       --php-memory-mb <MB>   memory_limit (MB)
       --php-max-exec <seg>   max_execution_time
       --php-max-input <seg>  max_input_time

Opciones All-in-One WP Migration:
       --ai1wm-bytes <bytes>  Nuevo valor para AI1WM_MAX_FILE_SIZE

Ejemplo interactivo típico:
  sudo bash \$(basename "\$0") --site traduccioneschino.es

Ejemplo no interactivo:
  sudo bash \$(basename "\$0") --site vendeenchina.es --no-interactive \\
       --install-wp \\
       --create-db --db-name wp_vende --db-user wp_vende --db-pass 'XXXX' \\
       --mysql-admin-user root --mysql-admin-pass 'ROOTPASS' \\
       --php-tune --php-upload-mb 2048 --php-memory-mb 1024 \\
       --php-max-exec 300 --php-max-input 300 \\
       --ai1wm-bytes 2147483648
EOF
}

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--site)            SITE="$2"; shift 2;;
    --root)               ROOT="$2"; shift 2;;

    --install-wp)         INSTALL_WP=true; shift;;
    --create-db)          CREATE_DB=true; shift;;
    --db-name)            DB_NAME="$2"; shift 2;;
    --db-user)            DB_USER="$2"; shift 2;;
    --db-pass)            DB_PASS="$2"; shift 2;;
    --db-host)            DB_HOST="$2"; shift 2;;
    --mysql-admin-user)   MYSQL_ADMIN_USER="$2"; shift 2;;
    --mysql-admin-pass)   MYSQL_ADMIN_PASS="$2"; shift 2;;

    --php-tune)           TUNE_PHP=true; shift;;
    --php-upload-mb)      PHP_UPLOAD_MB="$2"; shift 2;;
    --php-memory-mb)      PHP_MEMORY_MB="$2"; shift 2;;
    --php-max-exec)       PHP_MAX_EXEC="$2"; shift 2;;
    --php-max-input)      PHP_MAX_INPUT="$2"; shift 2;;

    --ai1wm-bytes)        AI1WM_BYTES="$2"; shift 2;;

    --no-interactive)     INTERACTIVE=false; shift;;
    -h|--help)            usage; exit 0;;
    *)                    err "Argumento no reconocido: $1 (usa --help)";;
  esac
done

# ---------- Validaciones básicas ----------
[[ $EUID -eq 0 ]] || err "Debes ejecutar este script con sudo/root."
[[ -n "$SITE" ]] || err "Debes indicar el dominio con --site <dominio>."
[[ -d /opt/bitnami/apache ]] || err "No se encontró /opt/bitnami/apache (no parece un stack Bitnami)."

SITEDIR="$ROOT/$SITE"
DOCROOT="$SITEDIR/htdocs"
WPCONFIG="$DOCROOT/wp-config.php"
AI1WM_CONSTANTS="$DOCROOT/wp-content/plugins/all-in-one-wp-migration/constants.php"

[[ -d "$DOCROOT" ]] || err "No existe el DocumentRoot esperado: $DOCROOT"

# ---------- Funciones auxiliares ----------

ask_yes_no_default_yes() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [S/n]: " reply
  reply="${reply:-S}"
  case "${reply,,}" in
    s|si|sí|y|yes) return 0 ;;
    *)            return 1 ;;
  esac
}

interactive_prompts() {
  if [[ "$INTERACTIVE" = false ]]; then
    log "Modo no interactivo: no se harán preguntas."
    return
  fi

  log "Modo interactivo activado: se harán preguntas para completar la configuración."

  # --- Instalación de WordPress ---
  if [[ ! -f "$WPCONFIG" ]]; then
    # Solo tiene sentido ofrecer instalar WP si no existe wp-config.php
    if ask_yes_no_default_yes "No se ha encontrado wp-config.php. ¿Quieres que el script descargue e instale WordPress en $DOCROOT?"; then
      INSTALL_WP=true
    fi
  fi

  # --- Creación de BD ---
  if [[ "$CREATE_DB" = false ]]; then
    if ask_yes_no_default_yes "¿Quieres que el script cree la base de datos y el usuario de WordPress?"; then
      CREATE_DB=true
    fi
  fi

  if [[ "$CREATE_DB" = true ]]; then
    if [[ -z "$DB_NAME" ]]; then
      read -r -p "Nombre de la base de datos (ej: wp_${SITE//./_}): " DB_NAME
      DB_NAME="${DB_NAME:-wp_${SITE//./_}}"
    fi
    if [[ -z "$DB_USER" ]]; then
      read -r -p "Usuario de la base de datos (ej: wp_${SITE//./_}): " DB_USER
      DB_USER="${DB_USER:-wp_${SITE//./_}}"
    fi
    if [[ -z "$DB_PASS" ]]; then
      read -r -s -p "Contraseña del usuario de BD: " DB_PASS
      echo ""
    fi
    if [[ -z "$DB_HOST" ]]; then
      read -r -p "Host de la base de datos [localhost]: " DB_HOST
      DB_HOST="${DB_HOST:-localhost}"
    fi
    if [[ -z "$MYSQL_ADMIN_USER" ]]; then
      read -r -p "Usuario administrador MySQL [root]: " MYSQL_ADMIN_USER
      MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-root}"
    fi
    if [[ -z "$MYSQL_ADMIN_PASS" ]]; then
      read -r -s -p "Contraseña del administrador MySQL (se usará para crear BD/usuario): " MYSQL_ADMIN_PASS
      echo ""
    fi
  fi

  # --- Ajuste de php.ini ---
  if [[ "$TUNE_PHP" = false ]]; then
    if ask_yes_no_default_yes "¿Quieres ajustar php.ini con valores amplios para migración (2GB upload, 1GB memoria, 300s de tiempo)?"; then
      TUNE_PHP=true
      [[ "$PHP_UPLOAD_MB" -eq 0 ]] && PHP_UPLOAD_MB=2048
      [[ "$PHP_MEMORY_MB" -eq 0 ]] && PHP_MEMORY_MB=1024
      [[ "$PHP_MAX_EXEC"  -eq 0 ]] && PHP_MAX_EXEC=300
      [[ "$PHP_MAX_INPUT" -eq 0 ]] && PHP_MAX_INPUT=300
    fi
  fi

  # --- Ajuste de AI1WM_MAX_FILE_SIZE ---
  if (( AI1WM_BYTES == 0 )) && [[ -f "$AI1WM_CONSTANTS" ]]; then
    if ask_yes_no_default_yes "Se ha detectado All-in-One WP Migration. ¿Quieres fijar AI1WM_MAX_FILE_SIZE a 2GB (2147483648 bytes)?"; then
      AI1WM_BYTES=2147483648
    fi
  fi
}

install_wordpress() {
  if [[ "$INSTALL_WP" = false ]]; then
    log "No se ha solicitado instalación automática de WordPress (--install-wp no presente)."
    return
  fi

  if [[ -f "$WPCONFIG" ]]; then
    warn "Ya existe wp-config.php en $WPCONFIG. Se asume que WordPress está instalado; se omite descarga."
    return
  fi

  if [[ -n "$(ls -A "$DOCROOT" 2>/dev/null || true)" ]]; then
    warn "El DocumentRoot $DOCROOT no está vacío. No se descargará WordPress para evitar sobrescribir contenido."
    return
  fi

  log "Descargando e instalando WordPress en $DOCROOT"

  sudo -u bitnami bash -c "
    set -Eeuo pipefail
    cd '$SITEDIR'
    wget -q https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    mv wordpress/* '$DOCROOT'/
    rmdir wordpress
    rm latest.tar.gz
  "

  log "WordPress descargado y desplegado en $DOCROOT"
}

create_database() {
  if [[ "$CREATE_DB" = false ]]; then
    log "No se ha solicitado creación de BD (--create-db no presente)."
    return
  fi

  log "Creando base de datos y usuario para WordPress"

  local MYSQL_CMD=()
  if [[ -n "$MYSQL_ADMIN_PASS" ]]; then
    MYSQL_CMD=(mysql -u"$MYSQL_ADMIN_USER" -p"$MYSQL_ADMIN_PASS" -h "$DB_HOST")
  else
    MYSQL_CMD=(mysql -u"$MYSQL_ADMIN_USER" -h "$DB_HOST")
  fi

  local SQL="
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
"

  log "Ejecutando SQL de creación de BD/usuario..."
  printf '%s\n' "$SQL" | "${MYSQL_CMD[@]}"

  log "Base de datos '$DB_NAME' y usuario '$DB_USER' creados (o ya existentes)."
}

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
    warn "No se puede ajustar FS_METHOD porque no existe $WPCONFIG (¿WordPress instalado?)."
    return
  fi

  log "Asegurando FS_METHOD=direct en wp-config.php"
  if grep -q "FS_METHOD" "$WPCONFIG"; then
    sed -i "s/define(\s*'FS_METHOD'.*/define('FS_METHOD', 'direct');/" "$WPCONFIG"
  else
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
$( [[ "$INSTALL_WP" = true ]] && echo " - (Opcional) Instalación de WordPress en htdocs (si procedía)." || echo " - Instalación de WordPress NO solicitada desde el script." )
$( [[ "$CREATE_DB" = true ]] && echo " - (Opcional) Creación de BD/usuario de WordPress (si procedía)." || echo " - Creación de BD/usuario NO solicitada desde el script." )
 - Permisos y propietarios ajustados (bitnami:daemon, 775/664).
 - FS_METHOD=direct asegurado en wp-config.php (si existía).
$( [[ "$TUNE_PHP" = true ]] && echo " - php.ini modificado con los parámetros indicados." || echo " - php.ini no modificado (no se pasó --php-tune)." )
$( (( AI1WM_BYTES > 0 )) && echo " - AI1WM_MAX_FILE_SIZE ajustado a ${AI1WM_BYTES} bytes (si el plugin existe)." || echo " - AI1WM_MAX_FILE_SIZE no modificado." )

Siguientes pasos recomendados:
 - Si aún no has completado la instalación de WordPress, entra en el navegador:
     http://$SITE/   (o usando /etc/hosts apuntando a la instancia)
 - Entrar al panel de WordPress (cuando esté instalado):
     http://$SITE/wp-admin/
 - Instalar o verificar el plugin All-in-One WP Migration.
 - Realizar la importación del backup de la web origen.
 - Una vez migrado y probado en HTTP, proceder con la fase de HTTPS (Let’s Encrypt).
EOF
}

# ---------- Ejecución ----------
log "Iniciando Fase 2 para el sitio: $SITE"

interactive_prompts
install_wordpress
create_database
fix_permissions
ensure_fs_method_direct
tune_php_ini
update_ai1wm_limit
summary

log "Fase 2 finalizada."
