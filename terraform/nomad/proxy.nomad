job "proxy" {
  datacenters = [ "home" ]

  group "traefik" {
    network {
      mode = "bridge"

      port "http" {
        to = 80
        static = 80
      }
      port "https" {
        to = 443
        static = 443
      }
    }

    service {
      name = "proxy-traefik"
      port = "https"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.traefik.rule=Host(`proxy.${domain}`)",
        "traefik.http.routers.traefik.entrypoints=websecure",
        "traefik.http.routers.traefik.service=api@internal",
      ]

      connect {
        sidecar_service {
          tags = []
          proxy {
            upstreams {
              destination_name = "proxy-acme-dns-api"
              local_bind_port  = 8000
            }
          }
        }
      }
    }

    task "proxy" {
      driver = "docker"

      env {
        ACME_DNS_API_BASE = "http://127.0.0.1:8000"
        ACME_DNS_STORAGE_PATH = "/letsencrypt/acme-dns"
        CONSUL_HTTP_TOKEN = "${consul_token}"
      }

      config {
        image = "traefik"
        volumes = ["/data/certs:/letsencrypt"]
        args = [
          "--api",
          "--ping",
          "--providers.consulcatalog.endpoint.address=http://${consul_address}",
          "--providers.consulcatalog.exposedbydefault=false",
          "--entrypoints.web.address=:80",
          "--entrypoints.web.http.redirections.entrypoint.to=websecure",
          "--entrypoints.web.http.redirections.entrypoint.scheme=https",
          "--entrypoints.websecure.address=:443",
          "--entrypoints.websecure.http.tls",
          "--entrypoints.websecure.http.tls.certresolver=lan",
          "--certificatesresolvers.lan.acme.dnschallenge",
          "--certificatesresolvers.lan.acme.dnschallenge.provider=acme-dns",
          "--certificatesresolvers.lan.acme.dnschallenge.resolvers=1.1.1.1",
          "--certificatesresolvers.lan.acme.email=${email}",
          "--certificatesresolvers.lan.acme.storage=/letsencrypt/acme.json",
        ]
      }
    }
  }

  group "acme" {
    network {
      mode = "bridge"

      port "dns" {
        static = 8053
        to = 8053
      }
      port "http" {
        to = 80
      }
    }

    service {
      name = "proxy-acme-dns-api"
      port = "http"

      connect {
        sidecar_service {}
      }
    }

    task "acme-dns" {
      driver = "docker"

      env {
        TZ = "${tz}"
      }

      config {
        image = "joohoi/acme-dns"

        volumes = [
          "/data/proxy/acme-dns.cfg:/etc/acme-dns/config.cfg:ro",
          "/data/proxy/acme-dns/:/var/lib/acme-dns/",
        ]
      }
    }
  }
}
