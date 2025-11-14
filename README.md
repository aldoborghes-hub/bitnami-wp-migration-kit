# bitnami-wp-migration-kit
utomatización completa para la gestión de múltiples sitios WordPress en instancias Bitnami (Lightsail / EC2) ste proyecto proporciona un conjunto de scripts automatizados, plantillas de configuración y una guía consolidada para gestionar múltiples sitios WordPress en una instalación Bitnami sin depender del WordPress “global” (/opt/bitnami/wordpres
# bitnami-wp-migration-kit
Automatización completa para crear y gestionar múltiples sitios WordPress en instancias Bitnami (Lightsail/EC2) sin depender del WordPress global.

Incluye scripts, plantillas y una guía única que sustituye todas las anteriores.

---

## 🚀 Objetivo del proyecto

Bitnami no está preparado para tener múltiples sitios WordPress limpios sin mezclar configuraciones.  
Este kit permite:

- Crear sitios aislados en `/opt/bitnami/sites/<dominio>`
- Generar VirtualHosts propios
- Instalar WordPress automáticamente (opcional)
- Importar sitios sin que interfieran entre ellos
- Aplicar configuraciones post-instalación de forma automática
- Integrar SMTP seguro con AWS SSM
- Estandarizar la estructura para futuras migraciones

---

## 📂 Estructura del repositorio

