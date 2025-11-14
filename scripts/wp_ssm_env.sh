#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: wp_ssm_env.sh
# Objetivo:
#   Leer parámetros SMTP desde AWS SSM Parameter Store y generar
#   /etc/wp-smtp-<SITE_ID>.env con variables de entorno para WordPress.
#
# Uso:
#   sudo SITE_ID=chinesetranslation STAGE=prod /usr/local/bin/wp_ssm_env.sh
#
# Requisitos:
#   - Perfil AWS configurado (~/.aws/credentials) con nombre: wp-ssm
#   - Parámetros en SSM: /wp/<STAGE>/<SITE_ID>/smtp/{host,port,from,user,pass}
# -----------------------------------------------------------------------------
set -euo pipefail

SITE_ID="${SITE_ID:-chinesetranslation}"
STAGE="${STAGE:-prod}"
REGION="${REGION:-eu-west-3}"
PROFILE="${AWS_PROFILE:-wp-ssm}"

BASE="/wp/${STAGE}/${SITE_ID}"
OUT="/etc/wp-smtp-${SITE_ID}.env"

get_str() {
  aws --profile "$PROFILE" ssm get-parameter \
    --region "$REGION" \
    --name "$1" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || true
}

get_sec() {
  aws --profile "$PROFILE" ssm get-parameter \
    --region "$REGION" \
    --with-decryption \
    --name "$1" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || true
}

HOST=$(get_str "$BASE/smtp/host")
PORT=$(get_str "$BASE/smtp/port")
FROM=$(get_str "$BASE/smtp/from")
USER=$(get_sec "$BASE/smtp/user")
PASS=$(get_sec "$BASE/smtp/pass")

if [[ -z "$HOST" || -z "$USER" || -z "$PASS" ]]; then
  echo "[ERROR] Faltan parámetros obligatorios en SSM para $BASE" >&2
  exit 1
fi

cat > "$OUT" <<ENVVARS
export WP_SMTP_HOST="$HOST"
export WP_SMTP_PORT="${PORT:-587}"
export WP_SMTP_FROM="$FROM"
export WP_SMTP_USER="$USER"
export WP_SMTP_PASS="$PASS"
ENVVARS

chmod 600 "$OUT"
echo "[INFO] Generado $OUT"
