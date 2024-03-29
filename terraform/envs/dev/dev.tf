# ------------------------------------------------------------
# Let terraform know about LXD.
# ------------------------------------------------------------
provider "lxd" {
  # This works using the local unix domain socket. You MUST be in the lxd group.
  generate_client_certificates = true
  accept_remote_certificate    = true
}


locals {
  domain      = "${var.datacentre}.${var.zone}"
  entrypoint  = "app.${var.datacentre}.${var.zone}"
}


provider "powerdns" {
  api_key    = var.pdns_api_key
  server_url = var.pdns_server_url
}


provider "consul" {
  address    = "[fd61:d025:74d7:f46a:216:3eff:fe0f:ec40]:8500"
  datacenter = var.datacentre
}

# ------------------------------------------------------------
# Postgresql container
# ------------------------------------------------------------
module "postgres" {
  source  = "./modules/turtle-container"
  name    = "postgres"
  image   = "engines/beowulf/base/20200701/0249/ci"
  zone    = local.domain
}

module "postgres_srv" {
  source    = "./modules/consul-service"
  srv_name  = "database"
  srv_port  = 5432
  srv_node  = "${module.postgres.name}"
  srv_addr  = "${module.postgres.ipv6_address}"
}


# ------------------------------------------------------------
# Application containers
# ------------------------------------------------------------
module "app0" {
  source  = "./modules/turtle-container"
  name    = "app0"
  image   = "engines/beowulf/base/20200701/0710"
  zone    = local.domain
}

module "app1" {
  source  = "./modules/turtle-container"
  name    = "app1"
  image   = "engines/beowulf/base/20200701/0710"
  zone    = local.domain
}

module "app2" {
  source  = "./modules/turtle-container"
  name    = "app2"
  image   = "engines/beowulf/base/20200701/0710"
  zone    = local.domain
}


resource "consul_key_prefix" "wap" {
  datacenter  = var.datacentre
  path_prefix = "traefik/"
  subkeys     = {
    "http/routers/app/entrypoints/0"                = "web"
    "http/routers/app/service"                      = "app"
    "http/routers/app/rule"                         = "Host(`${local.entrypoint}`)"
    "http/services/app/loadbalancer/servers/0/url"  = "http://${module.app0.name}.${local.domain}:3000/"
    "http/services/app/loadbalancer/servers/1/url"  = "http://${module.app1.name}.${local.domain}:3000/"
    "http/services/app/loadbalancer/servers/2/url"  = "http://${module.app2.name}.${local.domain}:3000/"
  }
}


# ------------------------------------------------------------
# Reverse HTTP Proxy container
# ------------------------------------------------------------
module "wap" {
  source  = "./modules/turtle-container"
  name    = "wap"
  image   = "engines/beowulf/base/20200701/0710"
  zone    = local.domain
}


# ------------------------------------------------------------
# Application DNS entry
# ------------------------------------------------------------
resource "powerdns_record" "app" {
  zone    = local.domain
  name    = "${local.entrypoint}."
  type    = "AAAA"
  ttl     = var.dns_ttl
  records = ["${module.wap.ipv6_address}"]
}
