module "magicentry_ingress" {
  source = "./ingress-block"

  namespace    = "auth"
  fqdn         = "auth.${var.domain}"
  mtls_enabled = false
  additional_annotations = {
    "cert-manager.io/cluster-issuer"           = "letsencrypt"
    "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
  }
}

resource "helm_release" "magicentry" {
  name             = "auth"
  namespace        = "auth"
  create_namespace = true
  atomic           = true

  repository = "oci://ghcr.io/dzervas/charts"
  chart      = "magicentry"
  version    = "0.7.1"
  values = [yamlencode({
    ingress = module.magicentry_ingress.host_obj
    persistence = {
      enabled = true
      size    = "1Gi"
    }

    image = {
      repository  = "ghcr.io/dzervas/magicentry"
      tag         = "sha-48be7c5-kube"
      pull_policy = "Always"
    }

    config = {
      title          = "DZerv.Art Auth Service"
      request_enable = false
      smtp_enable    = true
      smtp_url       = "smtp://noreply%40dzerv.art:${local.op_secrets.magicentry.mail_pass}@smtp.office365.com:587/?tls=required"
      smtp_from      = "DZerv.Art Auth Service <noreply@dzerv.art>"
      smtp_body      = "Click the link to login: <a href=\"{magic_link}\">Login</a>"

      external_url = "https://auth.dzerv.art"

      auth_url_user_header   = "X-Remote-User"
      auth_url_realms_header = "X-Remote-Group"

      services = [
        {
          name          = "Audiobooks"
          url           = "https://audiobooks.dzerv.art"
          valid_origins = ["https://audiobooks.dzerv.art"]
          realms        = ["audiobooks", "public"]

          auth_url = { origins = ["https://audiobooks.dzerv.art"] }

          oidc = {
            client_id     = local.op_secrets.magicentry.audiobooks_id
            client_secret = local.op_secrets.magicentry.audiobooks_secret
            redirect_urls = ["https://audiobooks.dzerv.art/auth/openid/callback"]
          }
        },
        {
          name          = "Retro Games"
          url           = "https://games.dzerv.art"
          valid_origins = ["https://games.dzerv.art"]
          realms        = ["games", "public"]

          auth_url = { origins = ["https://games.dzerv.art"] }

          oidc = {
            client_id     = local.op_secrets.magicentry.games_id
            client_secret = local.op_secrets.magicentry.games_secret
            redirect_urls = ["https://games.dzerv.art/api/oauth/openid"]
          }
        },
        {
          name          = "N8N"
          url           = "https://auto.dzerv.art"
          valid_origins = ["https://auto.dzerv.art"]
          realms        = ["n8n"]

          auth_url = { origins = ["https://auto.dzerv.art"] }

          oidc = {
            client_id     = local.op_secrets.magicentry.n8n_id
            client_secret = local.op_secrets.magicentry.n8n_secret
            redirect_urls = ["https://auto.dzerv.art/rest/sso/oidc/callback"]
          }
        },
        {
          name          = "Plane"
          url           = "https://projects.vpn.dzerv.art"
          valid_origins = ["https://projects.vpn.dzerv.art"]
          realms        = ["plane"]

          auth_url = {
            origins        = ["https://projects.vpn.dzerv.art"]
            status_url     = "http://plane-api.plane.svc:8000/api/users/me/"
            status_cookies = ["session-id"]
            status_headers = ["authorization"]
          }

          oidc = {
            client_id     = local.op_secrets.magicentry.plane_id
            client_secret = local.op_secrets.magicentry.plane_secret
            redirect_urls = [
              "https://projects.vpn.dzerv.art/auth/oidc/callback/",
              "https://projects.vpn.dzerv.art/auth/mobile/oidc/callback/"
            ]
          }
        },
      ]

      users = [
        { name = "Dimitris Zervas", email = "dzervas@dzervas.gr", username = "dzervas", realms = ["all"] },
        { name = "Fani", email = "fani-garouf@hotmail.com", username = "fani", realms = ["public", "audiobooks", "cook", "plane", "n8n"] },
        { name = "test", email = "dzervas@protonmail.com", username = "test", realms = ["audiobooks", "cook"] },

        { name = "Lilaki", email = "liliagkounisofikiti@hotmail.com", username = "lilia", realms = ["audiobooks"] },

        { name = "Giorgos Galanakis", email = "ggalan87@gmail.com", username = "ggalan87", realms = ["audiobooks"] },
        { name = "xiaflos", email = "asmolf@gmail.com", username = "xiaflos", realms = ["audiobooks"] },
        { name = "Alextrical", email = "benjackson990@gmail.com", username = "alextrical", realms = ["audiobooks"] },
        { name = "Darina Golos", email = "darinagolos@gmail.com", username = "darina", realms = ["audiobooks"] },
        { name = "Endri Meto", email = "audiobooks@endme.gr", username = "endme", realms = ["public"] },
        { name = "psof", email = "polidoros.sofikitis@gmail.com", username = "psof", realms = ["public", "cook", "n8n", "plane"] },
        { name = "John", email = "john.torakis@gmail.com", username = "john", realms = ["public", "plane"] },
      ]
    }
  })]
}

resource "kubernetes_network_policy_v1" "magicentry_ingress" {
  metadata {
    name      = "allow-magicentry-ingress"
    namespace = "auth"
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {}
        pod_selector {
          match_labels = {
            "magicentry.rs/enable" = "true"
          }
        }
      }
      # Allow traffic from the ingress controller for auth-url
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "traefik"
          }
        }
        pod_selector {
          # match_labels = {
          #   "magicentry.rs/enable" = "true"
          # }
        }
      }
      # ports {
      # protocol = "TCP"
      # port     = 8080
      # }
    }
  }
}
