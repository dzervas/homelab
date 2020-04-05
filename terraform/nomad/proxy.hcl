job "proxy" {
	type = "service"
	datacenters = [ "home" ]

	group "proxies" {
		task "proxy" {
			driver = "docker"

			service {
				port = "https"
              	name = "proxy"

				tags = [
					"traefik.enable=true",
					"traefik.http.routers.traefik.rule=Host(`proxy.${domain}`)",
					"traefik.http.routers.traefik.entrypoints=websecure",
					"traefik.http.routers.traefik.service=api@internal",
				]

//				check {
//					type = "http"
//					interval = "5s"
//					timeout = "2s"
//					path = "/ping"
//				}

				connect {
					sidecar_service {}
				}
			}

			env {
				ACME_DNS_API_BASE = "http://acme-dns"
				ACME_DNS_STORAGE_PATH = "/letsencrypt/acme-dns"
				CONSUL_HTTP_TOKEN = "${consul_token}"
			}

			config {
				image = "traefik"
				args = [
					"--log.level=DEBUG",
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

				volumes = [ "/data/certs:/letsencrypt" ]

				port_map = {
					http = 80
					https = 443
				}
			}

			resources {
				network {
					port "http" { static = "80" }
					port "https" { static = "443" }
				}
			}
		}

		task "acme-dns" {
			driver = "docker"

			env { TZ = "${tz}" }

			config {
				image = "joohoi/acme-dns"

				volumes = [
					"/data/proxy/acme-dns.cfg:/etc/acme-dns/config.cfg:ro",
					"/data/proxy/acme-dns/:/var/lib/acme-dns/",
				]

				port_map = { dns = 80 }
			}

			resources {
				network {
					// TODO: Limit access to VPN only
					port "dns" { static = "53" }
				}
			}
		}
	}
}
