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

```text
scripts/
    script_fase1_sitio_bitnami.sh
    script_fase2_post_wp.sh
    wp_ssm_env.sh
    wp-ssm@.service

docs/
    guia_migracion_bitnami.md
    ejemplos/
        ejemplo_vhost.conf
        ejemplo_setenv_append.txt
        arbol_directorios.txt

templates/
    vhost.conf.template
    ssm_parameters_template.txt
    estructura_sitio.txt
```

---

## ▶️ Uso rápido

### 1️⃣ Crear un nuevo sitio (Fase 1)

```bash
sudo ./scripts/script_fase1_sitio_bitnami.sh --site ejemplo.com --alias www.ejemplo.com
```

Esto crea:

- `/opt/bitnami/sites/ejemplo.com/htdocs`
- `/opt/bitnami/sites/ejemplo.com/conf/vhost.conf`
- Logs dedicados  
- Permisos correctos

---

### 2️⃣ Completar instalación o importar un backup

Luego acceder a:

```text
http://ejemplo.com/wp-admin
```

Completar el instalador de WordPress o importar una copia con el plugin elegido.

---

### 3️⃣ Ajustes post-instalación (Fase 2)

```bash
./scripts/script_fase2_post_wp.sh --site ejemplo.com
```

Esto corrige:

- `home` / `siteurl`
- Estructura de permalinks `/ %postname% /`
- `rewrite flush` duro

---

### 4️⃣ (Opcional) SMTP seguro con AWS SSM

```bash
sudo SITE_ID=ejemplo STAGE=prod /usr/local/bin/wp_ssm_env.sh
sudo systemctl enable --now wp-ssm@ejemplo.service
```

---

## 🧪 Probar sitio antes de apuntar DNS

En tu equipo local, editar el archivo `hosts`:

- En Windows: `C:\Windows\System32\drivers\etc\hosts`
- En Linux/Mac: `/etc/hosts`

Añadir:

```text
IP_PUBLICA ejemplo.com
IP_PUBLICA www.ejemplo.com
```

---

## 🛡 Licencia

MIT (puedes modificarla si quieres).

---

## 👤 Autor

Aldo — traduccioneschino.es  
Automatización avanzada WordPress + AWS + Bitnami
