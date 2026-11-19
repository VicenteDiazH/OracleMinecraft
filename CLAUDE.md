# CLAUDE.md — Proyecto: Minecraft Forge en Oracle Cloud con Terraform + Docker

> Este archivo es el contexto completo del proyecto. Léelo entero antes de hacer cualquier cosa.

---

## 1. Modo de trabajo: ENSEÑANZA (lo más importante)

El usuario es informático y quiere **aprender** Terraform, Oracle Cloud (OCI), cloud-init y Docker Compose mientras construye este proyecto. No quiere que le entreguen el repo hecho de una vez.

Reglas:

1. **Paso a paso.** Un archivo o un concepto a la vez. Nunca generes todo el repo de golpe.
2. **Primero el concepto, después el código.** Antes de cada archivo, explica en 3–6 líneas qué problema resuelve y qué conceptos nuevos aparecen (por ejemplo: "un `data source` lee algo que ya existe; un `resource` crea algo").
3. **Que el usuario participe.** Cuando sea razonable, pídele que escriba él una parte (una variable, una regla de firewall) y después revísala. Si prefiere que escribas tú, explica el código bloque por bloque después de escribirlo.
4. **Verifica que entendió.** Al cerrar cada fase, hazle 1 o 2 preguntas cortas (por ejemplo: "¿qué pasaría si cambiamos `user_data` sin el `ignore_changes`?").
5. **Explica el porqué de cada decisión** (ver sección 5). Si existe una alternativa razonable, menciónala en una línea.
6. **Corre los comandos con él** (`terraform init/plan/apply`, `docker compose config`) y explica cómo leer la salida, sobre todo el `plan`.
7. **Idioma:** español (el usuario es chileno). Los términos técnicos pueden quedar en inglés.
8. **Ritmo:** al final de cada paso, pregunta si seguimos o si quiere profundizar en algo.

---

## 2. Contexto (de dónde viene esto)

- El usuario y sus amigos juegan Minecraft **Forge 1.20.1 con unos 100 mods**.
- Antes lo corrían en un server casero (**Intel i3-4150**, 2 núcleos y 4 hilos, de 2014) con Docker y la imagen `itzg/minecraft-server`. Tenía mucho lag (bloques que reaparecen al romperlos, CPU al 130%), porque el hilo principal de Minecraft saturaba un núcleo lento.
- Descartaron Vultr High Frequency en Santiago (~US$96 al mes) por precio.
- **Decisión: Oracle Cloud Always Free, con instancia ARM Ampere A1.**
- **La cuenta ya está creada, con home region `Chile Central (Santiago)` = `sa-santiago-1`.** La home region no se puede cambiar.
- Objetivo del repo: que sea **público en GitHub**, sirva como **portafolio** y sea **funcional** (que el usuario lo use de verdad para su server).

---

## 3. Arquitectura objetivo

```
Jugadores (Chile) ──TCP 25565──► IP pública
                                    │
                    ┌───────────── OCI sa-santiago-1 ─────────────┐
                    │ VCN 10.0.0.0/16                              │
                    │  ├─ Internet Gateway + Route Table           │
                    │  └─ Subnet pública 10.0.1.0/24               │
                    │      Security List: 22 (solo mi IP), 25565   │
                    │                                              │
                    │   Instancia VM.Standard.A1.Flex (ARM)        │
                    │   Ubuntu 24.04 aarch64                       │
                    │   cloud-init: Docker + iptables + compose    │
                    │    ├─ contenedor mc (itzg/minecraft-server)  │
                    │    └─ contenedor backup (itzg/mc-backup)     │
                    │                                              │
                    │   Block Volume (50 GB) ─► /opt/minecraft/data│
                    │   (el mundo sobrevive si se recrea la VM)    │
                    └──────────────────────────────────────────────┘
```

---

## 4. Estructura del repo

```
minecraft-oci/
├── README.md                     # portafolio: qué es, diagrama, cómo usarlo, costos (US$0)
├── LICENSE                       # MIT
├── CLAUDE.md                     # este archivo
├── .gitignore
├── Makefile                      # init, plan, apply, destroy, ssh, logs, deploy, upload-world, backups, fmt, validate, local-up
├── terraform/
│   ├── versions.tf               # required_providers (oracle/oci >= 6.0) + provider "oci"
│   ├── variables.tf              # con validaciones (límites del free tier)
│   ├── network.tf                # VCN, IGW, route table, security list, subnet
│   ├── compute.tf                # data sources (AD, imagen) + instancia
│   ├── storage.tf                # block volume + attachment
│   ├── outputs.tf                # public_ip, ssh_command, server_address
│   ├── cloud-init.yaml.tftpl     # bootstrap de la VM
│   └── terraform.tfvars.example
├── docker/
│   ├── docker-compose.yml
│   └── .env.example              # versión de MC/Forge, RAM, distancias, RCON
├── scripts/
│   ├── upload-world.sh           # rsync del mundo y mods existentes a la VM
│   └── download-backups.sh       # trae los backups a local
└── .github/workflows/
    └── validate.yml              # terraform fmt -check + validate, docker compose config, shellcheck
```

---

## 5. Decisiones técnicas y su porqué (explícaselas al usuario)

### Oracle Cloud / Terraform
- **Provider:** `oracle/oci`, con autenticación por API key (tenancy_ocid, user_ocid, fingerprint, private_key_path, region). La API key se crea en la consola: perfil → User settings → API keys → Add API key.
- **Free tier:** varias fuentes de 2026 dicen que Oracle **bajó el Always Free de A1 de 4 OCPU / 24 GB a 2 OCPU / 12 GB**, pero no está 100% confirmado. Por defecto usamos `ocpus = 2` y `memory_gb = 12`, con `validation` en las variables (OCPU ≤ 4, RAM ≤ 24). Pídele al usuario que revise en la consola cuánto le ofrece.
- **Almacenamiento:** el free tier incluye 200 GB en total. Usamos un boot volume de unos 50 GB y un block volume de 50 GB (el mínimo de OCI).
- **Imagen:** `data "oci_core_images"` con `operating_system = "Canonical Ubuntu"`, `operating_system_version = "24.04"`, `shape = "VM.Standard.A1.Flex"`, `sort_by = "TIMECREATED"` y `sort_order = "DESC"`. El filtro por shape asegura que la imagen sea aarch64.
- **Availability domain:** `data "oci_identity_availability_domains"`, con una variable `availability_domain_index` (default 0) para poder cambiar de AD si aparece "Out of host capacity".
- **`lifecycle { ignore_changes = [source_details[0].source_id, metadata["user_data"]] }`:** sin esto, cada imagen nueva de Ubuntu o cada cambio en cloud-init **destruiría y recrearía la VM**. cloud-init solo se usa para el bootstrap inicial. Los cambios posteriores se aplican con `make deploy`.
- **Block volume separado para el mundo:** si la VM se recrea, el mundo no se pierde. El attachment es `paravirtualized`. En cloud-init hay un script que **espera** a que aparezca el disco (el attachment ocurre después del boot), lo formatea solo si no tiene filesystem, lo agrega a `/etc/fstab` con `nofail` y lo monta en `/opt/minecraft/data`. Para detectar el disco, el script busca el que no es el disco raíz (con `lsblk` y `findmnt`), en vez de asumir el nombre del dispositivo.
- **Security list:** el puerto 22 abierto solo para `var.ssh_allowed_cidr` (la IP del usuario /32) y el 25565 TCP abierto a 0.0.0.0/0. Egress, todo permitido.
- **IP pública efímera:** es suficiente, porque gracias al block volume recrear la VM casi nunca hace falta. Mejora opcional: una IP reservada (`oci_core_public_ip` con `lifetime = "RESERVED"`).

### cloud-init (trampas de OCI)
- **Las imágenes de Ubuntu de Oracle traen iptables restrictivo** (con un REJECT al final de INPUT). Hay que abrir el puerto 25565 **antes** de instalar Docker y guardar las reglas con `netfilter-persistent save`. Si se guardan después de instalar Docker, se persisten las reglas de Docker y eso trae problemas al reiniciar. El orden importa.
- Instalar `docker.io` y `docker-compose-v2` desde los repos de Ubuntu (más simple y reproducible que `curl | sh`).
- Escribir los archivos de compose y `.env` en `/opt/minecraft` con `write_files` (contenido en base64 vía `templatefile`).
- `chown -R 1000:1000 /opt/minecraft/data`, porque la imagen itzg corre con UID/GID 1000.
- Al final, `docker compose up -d`. Con `restart: unless-stopped` y el servicio de Docker habilitado, el server sobrevive a los reinicios.

### Docker
- Imagen `itzg/minecraft-server:java17` (Forge 1.20.1 requiere Java 17). La imagen es multi-arch, así que funciona en ARM.
- Variables: `TYPE=FORGE`, `VERSION=1.20.1`, `FORGE_VERSION` (la que usaban, a preguntar), `MEMORY` (unos 9G si la VM tiene 12 GB, unos 14G si tiene 24 GB), `USE_AIKAR_FLAGS=true`, `VIEW_DISTANCE=6`, `SIMULATION_DISTANCE=4`, `UID/GID=1000`, `RCON_PASSWORD`.
- **`docker/.env` es la única fuente de configuración del juego** (está en .gitignore; se versiona `.env.example`). Terraform lo lee con `fileexists()`/`file()` para el bootstrap, con `.env.example` como fallback. `make deploy` lo sincroniza después.
- `itzg/mc-backup` con `BACKUP_INTERVAL=6h`, `PRUNE_BACKUPS_DAYS=5` y RCON al contenedor `mc`. Los backups quedan en `/opt/minecraft/backups`.
- RCON **no** se publica al exterior.
- `make local-up` sirve para probar el compose en local.

### Rendimiento (lo aprendido con el server casero)
- Minecraft depende sobre todo de **un solo hilo**. Ampere A1 rinde parecido o algo mejor que el i3-4150, así que lo obligatorio es **pregenerar el mundo con Chunky** y usar distancias bajas.
- Mods de rendimiento recomendados para Forge: ModernFix, FerriteCore, Canary, AI Improvements, Clumps y Let Me Despawn. **FastChunkGen** es el port de C2ME para Forge 1.20.1 más estable; arregla la pérdida de datos de chunk de otros ports.
- **spark** (`/spark profiler`) sirve para encontrar qué mod consume más CPU.
- **ARM:** los mods con librerías nativas x86 pueden fallar. Si el server se cae al arrancar, hay que revisar el log.

### Seguridad (importante para un repo público)
- En `.gitignore`: `*.tfvars` (excepto `.example`), `*.tfstate*`, `.terraform/`, `*.pem`, llaves, `docker/.env`, `backups/` y `data/`.
- El **tfstate contiene datos sensibles**: nunca se commitea. Opcional: backend remoto en OCI Object Storage.
- No commitear OCIDs, IPs ni contraseñas en el README.

### Operación de la cuenta
- Recomendar el **upgrade a Pay As You Go**: sigue siendo gratis dentro de los límites, da prioridad cuando no hay capacidad y evita que Oracle recupere instancias inactivas. Además, configurar una **alerta de presupuesto** de US$1.
- Si aparece "Out of host capacity", probar otro AD o reintentar más tarde.

---

## 6. Plan de lecciones (fases)

Cada fase termina con algo que funciona y con preguntas de comprobación.

1. **Fundamentos y setup.** Qué es IaC, cómo funcionan Terraform y su state, y conceptos de OCI (tenancy, compartment, OCID, region, AD). Instalar Terraform y la OCI CLI (opcional), crear la API key, preparar `terraform.tfvars`, `.gitignore` y `git init`.
2. **Provider y primer `plan`.** `versions.tf` y `variables.tf` (tipos, defaults, validaciones, `sensitive`). Correr `terraform init` y explicar `.terraform.lock.hcl`.
3. **Red.** `network.tf`: VCN, Internet Gateway, route table, security list y subnet. `apply` de solo la red, y revisarla en la consola.
4. **Cómputo.** Data sources (AD, imagen), la instancia con `shape_config` y `outputs.tf`. Entrar por SSH a una VM vacía.
5. **cloud-init.** `templatefile`, `write_files`, el orden de iptables y Docker, y cómo depurar (`/var/log/cloud-init-output.log`, `cloud-init status`).
6. **Docker Compose.** `docker-compose.yml` y `.env.example`. Probar en local con `make local-up`.
7. **Almacenamiento persistente.** Block volume, attachment y el script de montaje. Probar que el mundo sobrevive a recrear la VM.
8. **Operación.** Makefile y scripts (`deploy`, `upload-world`, `backups`). Subir el mundo y los mods reales del usuario, y pregenerar con Chunky.
9. **CI y portafolio.** GitHub Actions, un README bonito (diagrama mermaid, badges, sección "qué aprendí"), LICENSE y publicar en GitHub.

---

## 7. Estado actual

- Todavía no hay código en la máquina del usuario: **se parte desde cero**, en la fase 1.
- Datos pendientes que hay que preguntarle al usuario cuando corresponda:
  - La `FORGE_VERSION` exacta y si los mods vienen de un modpack (CurseForge/Modrinth) o de una carpeta `mods/` manual.
  - Cuántos jugadores van a conectarse al mismo tiempo.
  - Si la consola le ofrece 2 OCPU / 12 GB o 4 OCPU / 24 GB.
  - Su usuario de GitHub y el nombre del repo.
  - Su IP pública para `ssh_allowed_cidr`.
