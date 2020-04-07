job "jira" {
  datacenters = [ "home" ]

  group "software" {
    network {
      mode = "bridge"

      port "http" {
        to = 8080
      }
    }

    service {
      name = "jira-software"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.jira.rule=Host(`jira.${domain}`)",
        "traefik.http.routers.jira.entrypoints=websecure",
      ]

      connect {
        sidecar_service {
          tags = []
          proxy {
            upstreams {
              destination_name = "jira-pgsql"
              local_bind_port  = 5432
            }
          }
        }
      }
    }

    task "jira" {
      driver = "docker"

      env {
        CATALINA_CONNECTOR_PROXYNAME = "jira.${domain}"
        CATALINA_CONNECTOR_PROXYPORT = 443
        CATALINA_CONNECTOR_SCHEME = "https"
        CATALINA_CONNECTOR_SECURE = "true"
        JVM_MINIMUM_MEMORY = "512m"
        JVM_MAXIMUM_MEMORY = "2048m"
      }

      config {
        image = "atlassian/jira-software"
        volumes = [ "/data/jira/jira:/var/atlassian/application-data/jira" ]
      }
    }
  }

  group "database" {
    network {
      mode = "bridge"

      port "pgsql" {
        to = 5432
      }
    }

    service {
      name = "jira-database"
      port = "pgsql"

      connect {
        sidecar_service {}
      }
    }

    task "postgresql" {
      driver = "docker"

      env {
        POSTGRES_USER = "jira"
        POSTGRES_DB = "jiradb"
        POSTGRES_ENCODING = "UNICODE"
        POSTGRES_COLLATE = "C"
        POSTGRES_COLLATE_TYPE = "C"
      }

      config {
        image = "postgres:11-alpine"
        volumes = [ "/data/jira/postgresql:/var/lib/postgresql/data" ]
      }
    }
  }
}
