locals {
  magicentry_users_audiobooks = [
    { name = "Fani", email = "fani-garouf@hotmail.com" }
  ]
}

module "magicentry_ingress" {
  source = "./ingress-block"

  fqdn         = "auth.${var.domain}"
  mtls_enabled = false
  additional_annotations = {
    "cert-manager.io/cluster-issuer"           = "letsencrypt"
    "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
    # "nginx.ingress.kubernetes.io/configuration-snippet" = <<EOF
    #   location /oidc/token {
    #     deny all;
    #     return 403;
    #   }
    # EOF
  }
}

resource "helm_release" "magicentry" {
  name             = "auth"
  namespace        = "auth"
  create_namespace = true
  atomic           = true

  repository = "oci://ghcr.io/dzervas/charts"
  chart      = "magicentry"
  version    = "0.4.9"
  values = [yamlencode({
    ingress = module.magicentry_ingress.host_obj
    persistence = {
      enabled      = true
      storageClass = "longhorn"
      size         = "1Gi"
    }

    config = {
      title          = "DZerv.Art Auth Service"
      request_enable = false
      smtp_enable    = true
      smtp_url       = "smtp://noreply%40dzerv.art:${local.op_secrets.magicentry.mail_pass}@smtp.office365.com:587/?tls=required"
      smtp_from      = "DZerv.Art Auth Service <noreply@dzerv.art>"
      smtp_body      = "Click the link to login: <a href=\"{magic_link}\">Login</a>"

      external_url = "https://auth.dzerv.art"

      oidc_enable = true
      oidc_clients = [
        {
          id            = local.op_secrets.magicentry.audiobooks_id
          secret        = local.op_secrets.magicentry.audiobooks_secret
          redirect_uris = ["https://audiobooks.dzerv.art/auth/openid/callback"]
          realms        = ["audiobooks", "public"]
        },
        {
          id     = local.op_secrets.magicentry.cook_id
          secret = local.op_secrets.magicentry.cook_secret
          redirect_uris = [
            "https://cook.dzerv.art/",
            "https://cook.dzerv.art/login/",
            "https://cook.dzerv.art/login/?direct=1"
          ]
          origins = ["https://cook.dzerv.art"]
          realms  = ["cook"]
        },
        {
          id            = local.op_secrets.magicentry.files_id
          secret        = local.op_secrets.magicentry.files_secret
          redirect_uris = ["https://files.dzerv.art/api/session/auth/"]
          realms        = ["files", "public"]
        },
      ]
      users = [
        { name = "Dimitris Zervas", email = "dzervas@dzervas.gr", username = "dzervas", realms = ["all"] },
        { name = "Fani", email = "fani-garouf@hotmail.com", username = "fani", realms = ["audiobooks", "cook"] },
        { name = "test", email = "dzervas@protonmail.com", username = "test", realms = ["audiobooks", "cook"] },

        { name = "Lilaki", email = "liliagkounisofikiti@hotmail.com", username = "lilia", realms = ["audiobooks"] },

        { name = "Giorgos Galanakis", email = "ggalan87@gmail.com", username = "ggalan87", realms = ["audiobooks"] },
        { name = "xiaflos", email = "asmolf@gmail.com", username = "xiaflos", realms = ["audiobooks"] },
        { name = "Alextrical", email = "benjackson990@gmail.com", username = "alextrical", realms = ["audiobooks"] },
        { name = "Darina Golos", email = "darinagolos@gmail.com", username = "darina", realms = ["audiobooks"] },
        { name = "Endri Meto", email = "audiobooks@endme.gr", username = "endme", realms = ["public"] },
        { name = "psof", email = "polidoros.sofikitis@gmail.com", username = "psof", realms = ["public", "cook"] },
      ]
    }
  })]
}
