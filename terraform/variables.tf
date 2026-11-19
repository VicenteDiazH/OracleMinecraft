# ─── Autenticación OCI ──────────────────────────────────────────

variable "tenancy_ocid" {
  description = "OCID de la tenancy (también se usa como compartment raíz)."
  type        = string

  validation {
    condition     = startswith(var.tenancy_ocid, "ocid1.tenancy.")
    error_message = "tenancy_ocid debe empezar con 'ocid1.tenancy.'."
  }
}

variable "user_ocid" {
  description = "OCID del usuario dueño de la API key."
  type        = string

  validation {
    condition     = startswith(var.user_ocid, "ocid1.user.")
    error_message = "user_ocid debe empezar con 'ocid1.user.'."
  }
}

variable "fingerprint" {
  description = "Fingerprint de la API key (aa:bb:cc:...)."
  type        = string
}

variable "private_key_path" {
  description = "Ruta a la llave privada de la API key (fuera del repo, ej: ~/.oci/oci_api_key.pem)."
  type        = string
}

variable "region" {
  description = "Región de OCI. Para Always Free tiene que ser la home region."
  type        = string
  default     = "sa-santiago-1"
}

variable "compartment_ocid" {
  description = "Compartment donde se crean los recursos. Si es null, se usa la tenancy (root)."
  type        = string
  default     = null
}

# ─── Proyecto / acceso ─────────────────────────────────────────

variable "project_name" {
  description = "Prefijo para los nombres de los recursos."
  type        = string
  default     = "minecraft"
}

variable "ssh_public_key_path" {
  description = "Llave pública SSH que se instala en la VM."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "Desde dónde se permite SSH. Tu IP pública con /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0)) && var.ssh_allowed_cidr != "0.0.0.0/0"
    error_message = "ssh_allowed_cidr debe ser un CIDR válido (ej: 190.1.2.3/32) y no puede ser 0.0.0.0/0."
  }
}

# ─── Cómputo (límites Always Free de Ampere A1) ────────────────

variable "availability_domain_index" {
  description = "Índice del AD a usar. Cámbialo si aparece 'Out of host capacity'."
  type        = number
  default     = 0
}

variable "instance_ocpus" {
  description = "OCPUs de la VM A1."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_ocpus >= 1 && var.instance_ocpus <= 4
    error_message = "Always Free permite máximo 4 OCPU de A1."
  }
}

variable "instance_memory_gb" {
  description = "RAM en GB de la VM A1."
  type        = number
  default     = 12

  validation {
    condition     = var.instance_memory_gb >= 1 && var.instance_memory_gb <= 24
    error_message = "Always Free permite máximo 24 GB de RAM en A1."
  }
}

# ─── Almacenamiento (Always Free = 200 GB en total) ────────────

variable "boot_volume_gb" {
  description = "Tamaño del disco de arranque."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_gb >= 50
    error_message = "OCI exige un boot volume de al menos 50 GB."
  }
}

variable "data_volume_gb" {
  description = "Tamaño del block volume para el mundo."
  type        = number
  default     = 50

  validation {
    condition     = var.data_volume_gb >= 50 && var.boot_volume_gb + var.data_volume_gb <= 200
    error_message = "El block volume debe tener al menos 50 GB y, sumado al boot volume, no pasar de 200 GB."
  }
}

# ─── Valores derivados ─────────────────────────────────────────

locals {
  # coalesce devuelve el primer valor que no sea null
  compartment_id = coalesce(var.compartment_ocid, var.tenancy_ocid)
}
