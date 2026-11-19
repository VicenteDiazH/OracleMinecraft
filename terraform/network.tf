# ─── VCN: la red privada ───────────────────────────────────────
resource "oci_core_vcn" "main" {
  compartment_id = local.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "${var.project_name}-vcn"
  dns_label      = "mcvcn"
}

# ─── Internet Gateway: la salida a internet ────────────────────
resource "oci_core_internet_gateway" "main" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id # ← referencia = dependencia implícita
  display_name   = "${var.project_name}-igw"
  enabled        = true
}

# ─── Route Table: todo el tráfico externo va al gateway ────────
resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# ─── Security List: el firewall de la subnet ───────────────────
# Protocolos se indican por número IANA: "1" ICMP, "6" TCP, "17" UDP, "all".
resource "oci_core_security_list" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-public-sl"

  # Salida: todo permitido (apt, descargar mods, Docker Hub...)
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH solo desde tu IP
  ingress_security_rules {
    description = "SSH desde mi IP"
    source      = var.ssh_allowed_cidr
    protocol    = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Minecraft: abierto a todo internet (los jugadores se conectan desde cualquier IP)
  ingress_security_rules {
    description = "Minecraft Java"
    source      = "0.0.0.0/0"
    protocol    = "6"

    tcp_options {
      min = 25565
      max = 25565
    }
  }

  # ICMP tipo 3 código 4 ("fragmentation needed"): necesario para Path MTU Discovery.
  # Sin esto, algunas conexiones se cuelgan con paquetes grandes. OCI lo trae por defecto.
  ingress_security_rules {
    description = "ICMP path MTU discovery"
    source      = "0.0.0.0/0"
    protocol    = "1"

    icmp_options {
      type = 3
      code = 4
    }
  }
}

# ─── Subnet pública: donde vive la VM ──────────────────────────
resource "oci_core_subnet" "public" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "${var.project_name}-public-subnet"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false # permite que la VM tenga IP pública
}
