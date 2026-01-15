#!/usr/bin/env python3
"""
Crea (si no existe) una identidad de dominio en Amazon SES (SES v2).

Uso:
  python ses_crear_identidad.py vendeenchina.es

Requisitos:
  - Credenciales AWS configuradas (aws configure).
  - Permisos SES en la cuenta.
  - Región: eu-west-1 (Irlanda).
"""
#Desarrollado por Aldo Borghes
import sys
import boto3
from botocore.exceptions import ClientError


REGION = "eu-west-1"  # SES en Irlanda


def ensure_ses_domain_identity(domain: str):
    ses = boto3.client("sesv2", region_name=REGION)

    # 1) Comprobar si la identidad ya existe
    try:
        resp = ses.get_email_identity(EmailIdentity=domain)
        print(f"[INFO] La identidad SES para {domain} YA existe.")
        print(f"       Estado de verificación actual: {resp.get('VerificationStatus')}")
        return
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code != "NotFoundException":
            print(f"[ERROR] Error al consultar identidad SES: {e}")
            sys.exit(1)
        print(f"[INFO] La identidad SES para {domain} NO existe todavía. Se va a crear...")

    # 2) Crear la identidad
    try:
        ses.create_email_identity(EmailIdentity=domain)
        print(f"[OK] Identidad SES creada para el dominio: {domain}")
        print("    Ahora deberías ver el dominio en SES → Verified identities.")
        print("    Desde la consola podrás ver los registros DNS (TXT + DKIM).")
    except ClientError as e:
        print(f"[ERROR] Error al crear identidad SES: {e}")
        sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print("Uso:")
        print(f"  {sys.argv[0]} <dominio>")
        print("Ejemplo:")
        print(f"  {sys.argv[0]} vendeenchina.es")
        sys.exit(1)

    domain = sys.argv[1].strip()
    ensure_ses_domain_identity(domain)


if __name__ == "__main__":
    main()
