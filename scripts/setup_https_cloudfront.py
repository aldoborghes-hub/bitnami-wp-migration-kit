#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#Desarrollado por Aldo Borghes
import boto3
import time
import sys

# Hosted zone fija de CloudFront (no tocar)
CLOUDFRONT_HOSTED_ZONE_ID = "Z2FDTNDATAQYW2"

# Tiempos de espera
MAX_WAIT_CERT_SECONDS = 1800  # 30 minutos para emisión del cert
MAX_WAIT_DVO_SECONDS = 600    # 10 minutos para que ACM genere los CNAME
POLL_INTERVAL_SECONDS = 30


def pedir_datos():
    print("=== Configuración HTTPS con ACM + CloudFront + Route 53 ===\n")

    domain = input("Dominio principal (ej. vendeenchina.es): ").strip()
    if not domain:
        print("[FATAL] No has introducido dominio.")
        sys.exit(1)

    origin = input(
        "Origen de la web (IP o dominio del servidor en AWS, ej. 51.44.1.114 o miweb.paris.lightsail): "
    ).strip()
    if not origin:
        print("[FATAL] No has introducido el origen de la web.")
        sys.exit(1)

    hosted_zone_id = input(
        "Hosted Zone ID de Route 53 para este dominio (ej. Z0123456789ABCDEFG): "
    ).strip()
    if not hosted_zone_id:
        print("[FATAL] No has introducido el Hosted Zone ID.")
        sys.exit(1)

    print("\nResumen de datos:")
    print(f"  Dominio principal: {domain}")
    print(f"  Dominio www:       www.{domain}")
    print(f"  Origen web:        {origin}")
    print(f"  Hosted Zone ID:    {hosted_zone_id}")

    confirm = input("\n¿Confirmas que estos datos son correctos? (yes/no): ").strip().lower()
    if confirm not in ("yes", "y", "si", "sí"):
        print("Cancelado por el usuario.")
        sys.exit(0)

    return domain, origin, hosted_zone_id


def request_certificate(domain: str) -> str:
    """
    Solicita un certificado público en ACM (us-east-1) para:
      - domain
      - www.domain
    con validación DNS.
    """
    acm = boto3.client("acm", region_name="us-east-1")

    print(f"\n[INFO] Solicitando certificado en ACM (us-east-1) para {domain} y www.{domain}...")

    response = acm.request_certificate(
        DomainName=domain,
        ValidationMethod="DNS",
        SubjectAlternativeNames=[f"www.{domain}"],
        Options={
            "CertificateTransparencyLoggingPreference": "ENABLED"
        }
    )

    cert_arn = response["CertificateArn"]
    print(f"[OK] Certificado solicitado. ARN: {cert_arn}")
    return cert_arn


def wait_for_dvo_records(cert_arn: str):
    """
    Espera a que ACM genere los ResourceRecord (CNAME) de validación.
    Sin esto, no podemos crear los CNAME en Route 53.
    """
    acm = boto3.client("acm", region_name="us-east-1")
    print("\n[INFO] Esperando a que ACM genere los CNAME de validación...")

    elapsed = 0
    while elapsed < MAX_WAIT_DVO_SECONDS:
        cert = acm.describe_certificate(CertificateArn=cert_arn)
        dvos = cert["Certificate"].get("DomainValidationOptions", [])

        ready = True
        if not dvos:
            ready = False
        else:
            for dvo in dvos:
                rr = dvo.get("ResourceRecord")
                if not rr:
                    ready = False
                    break

        if ready and dvos:
            print("[OK] ACM ha generado los ResourceRecord de validación.")
            return dvos

        print(f"  - Aún no hay ResourceRecord disponibles (t+{elapsed}s).")
        time.sleep(POLL_INTERVAL_SECONDS)
        elapsed += POLL_INTERVAL_SECONDS

    print("[ERROR] ACM no ha generado los ResourceRecord en el tiempo esperado.")
    return []


def create_dns_validation_records(dvos, hosted_zone_id: str):
    """
    Crea en Route 53 los CNAME de validación que pide ACM.
    """
    if not dvos:
        print("[FATAL] No hay DomainValidationOptions con ResourceRecord. No se pueden crear CNAME.")
        sys.exit(1)

    r53 = boto3.client("route53")

    print("\n[INFO] Creando registros DNS de validación en Route 53...")

    changes = []
    for dvo in dvos:
        rr = dvo.get("ResourceRecord")
        if not rr:
            continue
        name = rr["Name"]
        value = rr["Value"]
        print(f"  - CNAME {name} -> {value}")

        changes.append(
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": name,
                    "Type": "CNAME",
                    "TTL": 300,
                    "ResourceRecords": [{"Value": value}],
                },
            }
        )

    if not changes:
        print("[FATAL] No se han podido construir cambios para Route 53.")
        sys.exit(1)

    r53.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            "Comment": "Registros de validación ACM creados por script",
            "Changes": changes,
        },
    )

    print("[OK] Registros de validación creados/actualizados en Route 53.")


def wait_for_certificate_issued(cert_arn: str) -> bool:
    """
    Espera hasta que el certificado pase a estado ISSUED o se agote el tiempo.
    """
    acm = boto3.client("acm", region_name="us-east-1")
    print("\n[INFO] Esperando a que el certificado esté en estado ISSUED...")

    elapsed = 0
    while elapsed < MAX_WAIT_CERT_SECONDS:
        cert = acm.describe_certificate(CertificateArn=cert_arn)
        status = cert["Certificate"]["Status"]
        print(f"  - Estado actual del certificado: {status} (t+{elapsed}s)")

        if status == "ISSUED":
            print("[OK] Certificado en estado ISSUED.")
            return True
        elif status in ("PENDING_VALIDATION", "INACTIVE"):
            time.sleep(POLL_INTERVAL_SECONDS)
            elapsed += POLL_INTERVAL_SECONDS
        else:
            print(f"[ERROR] Certificado en estado inesperado: {status}")
            return False

    print("[ERROR] Tiempo máximo de espera agotado sin que el certificado se emita.")
    return False


def create_cloudfront_distribution(domain: str, origin: str, cert_arn: str):
    """
    Crea una distribución de CloudFront con:
      - Origen = origin
      - Aliases = domain, www.domain
      - Certificado ACM = cert_arn
    """
    cf = boto3.client("cloudfront")

    print("\n[INFO] Creando distribución de CloudFront...")

    dist_config = {
        "CallerReference": f"setup-https-{domain}-{int(time.time())}",
        "Comment": f"Distribución para {domain} creada por script",
        "Enabled": True,
        "Origins": {
            "Quantity": 1,
            "Items": [
                {
                    "Id": "origin-1",
                    "DomainName": origin,
                    "CustomOriginConfig": {
                        "HTTPPort": 80,
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "http-only",  # cambia a "https-only" si tu Lightsail ya sirve HTTPS
                        "OriginSslProtocols": {
                            "Quantity": 1,
                            "Items": ["TLSv1.2"],
                        },
                        "OriginReadTimeout": 30,
                        "OriginKeepaliveTimeout": 5,
                    },
                }
            ],
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "origin-1",
            "ViewerProtocolPolicy": "redirect-to-https",
            "TrustedSigners": {"Enabled": False, "Quantity": 0},
            "AllowedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"],
                "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]},
            },
            "ForwardedValues": {
                "QueryString": True,
                "Cookies": {"Forward": "all"},
                "Headers": {
                    "Quantity": 1,
                    "Items": ["Host"],  # muy importante para que el origen sepa qué dominio se pidió
                },
            },
            "MinTTL": 0,
        },
        "Aliases": {
            "Quantity": 2,
            "Items": [domain, f"www.{domain}"],
        },
        "ViewerCertificate": {
            "ACMCertificateArn": cert_arn,
            "SSLSupportMethod": "sni-only",
            "MinimumProtocolVersion": "TLSv1.2_2021",
        },
        "PriceClass": "PriceClass_100",
        "IsIPV6Enabled": True,
    }

    resp = cf.create_distribution(DistributionConfig=dist_config)
    dist = resp["Distribution"]
    dist_id = dist["Id"]
    dist_domain = dist["DomainName"]

    print(f"[OK] Distribución creada. ID: {dist_id}")
    print(f"     DomainName CloudFront: {dist_domain}")

    return dist_id, dist_domain


def create_route53_alias_records(domain: str, hosted_zone_id: str, cf_domain: str):
    """
    Crea los registros A (Alias) en Route 53:
      - dominio raíz (domain) -> CloudFront
      - www.domain -> CloudFront
    """
    r53 = boto3.client("route53")

    print("\n[INFO] Creando registros A (Alias) en Route 53 apuntando a CloudFront...")

    changes = []

    # dominio raíz
    changes.append(
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": domain,
                "Type": "A",
                "AliasTarget": {
                    "HostedZoneId": CLOUDFRONT_HOSTED_ZONE_ID,
                    "DNSName": cf_domain,
                    "EvaluateTargetHealth": False,
                },
            },
        }
    )

    # www
    changes.append(
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": f"www.{domain}",
                "Type": "A",
                "AliasTarget": {
                    "HostedZoneId": CLOUDFRONT_HOSTED_ZONE_ID,
                    "DNSName": cf_domain,
                    "EvaluateTargetHealth": False,
                },
            },
        }
    )

    r53.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            "Comment": "Alias a CloudFront creados por script",
            "Changes": changes,
        },
    )

    print("[OK] Registros Alias creados/actualizados en Route 53.")


def main():
    domain, origin, hosted_zone_id = pedir_datos()

    # 1) Certificado ACM
    cert_arn = request_certificate(domain)

    # 2) Esperar a que ACM genere los CNAME de validación
    dvos = wait_for_dvo_records(cert_arn)
    if not dvos:
        print("\n[ERROR] No se han obtenido DomainValidationOptions con ResourceRecord.")
        sys.exit(1)

    # 3) Crear CNAME de validación en Route53
    create_dns_validation_records(dvos, hosted_zone_id)

    # 4) Esperar a que el certificado esté ISSUED
    ok = wait_for_certificate_issued(cert_arn)
    if not ok:
        print("\n[ERROR] El certificado no ha llegado a ISSUED. Revisa la consola de ACM.")
        sys.exit(1)

    # 5) Crear distribución de CloudFront
    dist_id, dist_domain = create_cloudfront_distribution(domain, origin, cert_arn)

    # 6) Crear alias en Route53
    create_route53_alias_records(domain, hosted_zone_id, dist_domain)

    print("\n===========================================")
    print("   Configuración HTTPS con CloudFront lista")
    print("===========================================")
    print(f" - Dominio raíz:      https://{domain}")
    print(f" - Dominio www:       https://www.{domain}")
    print(f" - CloudFront domain: https://{dist_domain}")
    print("")
    print("Recuerda:")
    print(" - La propagación de CloudFront y DNS puede tardar 5–20 minutos.")
    print(" - Prueba en modo incógnito y revisa el candado del navegador.")
    print("===========================================\n")


if __name__ == "__main__":
    main()
