# Guía Única de Migración WordPress en Bitnami (Fases 1–3)

> Entorno objetivo  
> - Instancia Bitnami WordPress en AWS (Lightsail o EC2).  
> - Multi-sitio manual usando `/opt/bitnami/sites/<dominio>/`.  
> - Cada dominio tiene su propio WordPress aislado.

## 0. Visión general

Cada migración de sitio WordPress se divide en 3 fases:

1. **Fase 1 – Alta del sitio en Bitnami**  
   Crear estructura de directorios, VirtualHost de Apache e instalar (si se desea) un WordPress limpio.

2. **Fase 2 – Ajustes de WordPress tras instalación / importación**  
   Ajustar `home` y `siteurl`, configurar enlaces permanentes y forzar `rewrite flush`.

3. **Fase 3 – SMTP seguro con AWS SSM** (opcional, pero recomendado)  
   Cargar credenciales SMTP desde AWS SSM Parameter Store mediante un script y un servicio systemd.

## 1. Preparación inicial del servidor (una sola vez)

1. Entrar como `bitnami` en la instancia:

   ```bash
   ssh -i <tu_clave> bitnami@IP_PUBLICA
   ```

2. Copiar los scripts al home de `bitnami`:

   - `/home/bitnami/script_fase1_sitio_bitnami.sh`
   - `/home/bitnami/script_fase2_post_wp.sh`

   Y dar permisos:

   ```bash
   cd /home/bitnami
   chmod +x script_fase1_sitio_bitnami.sh
   chmod +x script_fase2_post_wp.sh
   ```

3. Copiar y activar el script de SMTP (si se va a usar Fase 3):

   - `/usr/local/bin/wp_ssm_env.sh`
   - `/etc/systemd/system/wp-ssm@.service`

   Y dar permisos / recargar systemd:

   ```bash
   sudo chmod +x /usr/local/bin/wp_ssm_env.sh
   sudo systemctl daemon-reload
   ```

## 2. Fase 1 – Alta de un nuevo sitio en Bitnami

Ejemplo:

```bash
sudo ./script_fase1_sitio_bitnami.sh \
  --site vendeenchina.es \
  --alias www.vendeenchina.es
```

Esto crea `/opt/bitnami/sites/<dominio>`, genera el VirtualHost y opcionalmente instala WordPress.

## 3. Fase 2 – Ajustes tras instalación / importación

Se ejecuta una vez finalizada la instalación o importación:

```bash
su - bitnami
./script_fase2_post_wp.sh --site vendeenchina.es
```

Corrige:

- `home` / `siteurl`
- Permalinks `/ %postname% /`
- `rewrite flush`

## 4. Fase 3 – SMTP seguro con AWS SSM (opcional)

Se usan parámetros SSM bajo `/wp/<STAGE>/<SITE_ID>/smtp/...` y el script:

```bash
sudo SITE_ID=chinesetranslation STAGE=prod /usr/local/bin/wp_ssm_env.sh
sudo systemctl enable --now wp-ssm@chinesetranslation.service
```

Esto genera `/etc/wp-smtp-<SITE_ID>.env` con variables de entorno para SMTP.

## 5. Flujo resumido de migración

1. Fase 1: crear sitio y VirtualHost.
2. Instalar WP o importar backup.
3. Fase 2: ajustar URLs y permalinks.
4. Fase 3: (opcional) configurar SMTP seguro.
5. Probar sitio con /etc/hosts antes de tocar DNS.
