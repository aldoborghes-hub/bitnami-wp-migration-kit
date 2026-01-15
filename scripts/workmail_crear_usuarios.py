#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#Desarrollado por Aldo Borghes
import os
import sys
import boto3
from botocore.exceptions import ClientError
import getpass


# ==========================
# CONFIGURACIÓN BÁSICA
# ==========================

# Pon aquí tu OrganizationId de WorkMail
ORGANIZATION_ID = os.environ.get("WORKMAIL_ORG_ID", "PON_AQUI_TU_ORGANIZATION_ID")

# Región donde está WorkMail (cámbiala si usas otra)
AWS_REGION = os.environ.get("AWS_REGION", "eu-west-1")  # ej. eu-west-1 (Irlanda)


# ==========================
# CLIENTE DE WORKMAIL
# ==========================

def get_workmail_client():
    """
    Devuelve un cliente de WorkMail usando la región configurada.
    Requiere tener credenciales AWS configuradas (perfil, variables de entorno, etc.).
    """
    return boto3.client("workmail", region_name=AWS_REGION)


# ==========================
# FUNCIONES DE DOMINIO
# ==========================

def check_domain_in_org(org_id: str, domain: str) -> tuple[bool, bool | None]:
    """
    Comprueba si el dominio está registrado en la organización de WorkMail.
    Devuelve (existe, verificado):
      - existe: True/False
      - verificado: True/False/None (None si no se puede determinar)
    """
    wm = get_workmail_client()
    try:
        paginator = wm.get_paginator("list_mail_domains")
        for page in paginator.paginate(OrganizationId=org_id):
            for d in page.get("MailDomains", []):
                name = d.get("DomainName")
                if name and name.lower() == domain.lower():
                    # La clave puede llamarse "IsVerified" o "Verified" según versión
                    verified = (
                        d.get("IsVerified")
                        if "IsVerified" in d
                        else d.get("Verified")
                    )
                    return True, bool(verified) if verified is not None else None
        return False, None
    except ClientError as e:
        print(f"[WARN] No se ha podido listar dominios de WorkMail: {e}")
        return False, None


# ==========================
# FUNCIONES DE USUARIOS
# ==========================

def normalizar_usuario(raw_user: str, default_domain: str):
    """
    Devuelve (email, nombre_interno) a partir de lo que ha tecleado el usuario.

    Reglas:
    - Si no lleva @, se asume el dominio por defecto.
    - Si lleva @ pero el dominio no coincide con el indicado al inicio,
      se fuerza al dominio por defecto (y se avisa).
    - nombre_interno = local + '-' + dominio_sin_puntos
      (ej: info@vendeenchina.es -> info-vendeenchina-es)
    """
    raw_user = raw_user.strip()
    if not raw_user:
        return None

    default_domain = default_domain.strip()

    if "@" in raw_user:
        local, dom = raw_user.split("@", 1)
        local = local.strip()
        dom = (dom or default_domain).strip()
        if dom.lower() != default_domain.lower():
            print(
                f"[WARN] '{raw_user}' tiene dominio '{dom}', pero has indicado "
                f"'{default_domain}'. Se usará el dominio principal."
            )
            dom = default_domain
    else:
        local = raw_user
        dom = default_domain

    email = f"{local}@{dom}"
    nombre_interno = f"{local}-{dom.replace('.', '-')}"
    return email, nombre_interno


def find_user_by_name(org_id: str, user_name: str) -> str | None:
    """
    Busca un usuario por su 'Name' (nombre interno) en WorkMail.
    Devuelve el UserId o None si no existe.
    """
    wm = get
