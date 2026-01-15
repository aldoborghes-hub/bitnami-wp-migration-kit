#!/usr/bin/env python3
"""
Fase 4 – DNS en Route 53 para un dominio nuevo (modelo base)

Qué hace:
- Crea una Hosted Zone pública para el dominio (si no existe).
- Devuelve los NameServers para configurar en GoDaddy (más adelante).
- Crea registros básicos:
    - A (apex) -> IP Lightsail
    - CNAME www -> dominio
    - MX -> WorkMail (ejemplo eu-west-1)
    - TXT SPF genérico para SES/WorkMail

NO toca GoDaddy. Los NS se cambian a mano cuando todo esté listo.
"""
#Desarrollado por Aldo Borghes
import sys
import boto3
from botocore.exceptions import ClientError

route53 = boto3.client("route53")


def get_hosted_zone(domain: str):
    """Devuelve la Hosted Zone si existe, si no None."""
    resp = route53.list_hosted_zones_by_name(DNSName=domain, MaxItems="1")
    zones = resp.get("HostedZones", [])
    if zones and zones[0]["Name"].rstrip(".") == domain.rstrip("."):
        return zones[0]
    return None


def create_hosted_zone(domain: str) -> dict:
    """Crea una Hosted Zone pública para el dominio."""
    print(f"[INFO] Creando Hosted Zone pública para {domain}...")
    resp = route53.create_hosted_zone(
        Name=domain,
        CallerReference=domain,
        HostedZoneConfig={
            "Comment": f"Hosted zone para {domain} (creada por script)",
            "PrivateZone": False,
        },
    )
    return resp


def upsert_records(hosted_zone_id: str, domain: str, ip: str, region: str = "eu-west-1"):
    """Crea/actualiza los registros básicos A, CNAME, MX, TXT (SPF)."""
    apex = domain.rstrip(".")
    www = f"www.{apex}"

    # MX de ejemplo para WorkMail/SES en eu-west-1
    mx_value = f"10 inbound-smtp.{region}.amazonaws.com."

    # SPF genérico para SES/WorkMail
    spf_value = '"v=spf1 include:amazonses.com ~all"'

    changes = [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": apex + ".",
                "Type": "A",
                "TTL": 300,
                "ResourceRecords": [{"Value": ip}],
            },
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": www + ".",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [{"Value": apex + "."}],
            },
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": apex + ".",
                "Type": "MX",
                "TTL": 300,
                "ResourceRecords": [{"Value": mx_value}],
            },
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": apex + ".",
                "Type": "TXT",
                "TTL": 300,
                "ResourceRecords": [{"Value": spf_value}],
            },
        },
    ]

    print(f"[INFO] Creando/actualizando registros básicos en la Hosted Zone {hosted_zone_id}...")
    route53.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            "Comment": f"Registros básicos para {domain}",
            "Changes": changes,
        },
    )
    print("[INFO] Registros básicos creados/actualizados.")


def main():
    if len(sys.argv) < 3:
        print("Uso:")
        print(f"  {sys.argv[0]} <dominio> <ip_lightsail> [region_smtp]")
        print("Ejemplo:")
        print(f"  {sys.argv[0]} vendeenchina.es 51.44.1.114 eu-west-1")
        sys.exit(1)

    domain = sys.argv[1].strip()
    ip = sys.argv[2].strip()
    region = sys.argv[3].strip() if len(sys.argv) > 3 else "eu-west-1"

    try:
        zone = get_hosted_zone(domain)
        if zone:
            print(f"[INFO] Hosted Zone ya existe para {domain}.")
            hz_id = zone["Id"].split("/")[-1]
            delegation = route53.get_hosted_zone(Id=zone["Id"])
            nameservers = delegation["DelegationSet"]["NameServers"]
        else:
            resp = create_hosted_zone(domain)
            hz_id = resp["HostedZone"]["Id"].split("/")[-1]
            nameservers = resp["DelegationSet"]["NameServers"]
            print(f"[INFO] Hosted Zone creada con ID: {hz_id}")

        print("\n[INFO] Nameservers de Route 53 (para poner en GoDaddy CUANDO TOQUE):")
        for ns in nameservers:
            print(f"  - {ns}")

        upsert_records(hz_id, domain, ip, region)

        print("\n[OK] Configuración DNS básica en Route 53 completa.")
        print("Ahora puedes:")
        print("  1) Añadir/ajustar registros SES/WorkMail (DKIM, verificación, DMARC...).")
        print("  2) Cuando todo esté listo, cambiar los NS en GoDaddy a los anteriores.")
    except ClientError as e:
        print(f"[ERROR] Error de AWS: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
print("\n")
print("===========================================")
print("   IMPORTANTE – ACCIÓN MANUAL REQUERIDA")
print("===========================================")
print("Debes copiar los 4 Nameservers (NS) que Route 53 ha generado")
print("para este dominio y configurarlos en tu proveedor de dominio")
print("(por ejemplo, GoDaddy).")
print("")
print("Instrucciones:")
print("  1. Ve a AWS → Route 53 → Hosted Zones → tu dominio.")
print("  2. Busca el registro de tipo NS.")
print("  3. Copia los 4 servidores NS tal cual aparecen, PERO:")
print("       - Elimínales el punto final (.)")
print("       - Pégalos en GoDaddy como \"Custom nameservers\"")
print("")
print("Muy importante:")
print("  - Hasta que cambies los Nameservers, este dominio no")
print("    resolverá desde Route 53.")
print("  - WorkMail NO podrá verificar el dominio.")
print("  - No podrás crear buzones WorkMail sin que el dominio")
print("    aparezca como VERIFIED.")
print("")
print("Después de cambiar los nameservers, espera entre 20–60 minutos")
print("hasta que la propagación se complete y el dominio aparezca como")
print("VERIFIED en SES y WorkMail.")
print("===========================================")
print("\n")
