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
  version    = "0.4.2"
  values = [yamlencode({
    ingress = module.magicentry_ingress.host_obj
    persistence = {
      enabled      = true
      storageClass = "longhorn"
      size         = "1Gi"
    }

    config = {
      title          = "DZerv.Art Auth Service"
      request_enable = true # Defaults to CI Notify
      request_data   = "to={email}&subject={title} Login&body=Click the link to login: <a href=\"{magic_link}\">Login</a>&type=text/html"
      external_url   = "https://auth.dzerv.art"

      oidc_enable = true
      oidc_clients = [
        {
          id            = "u5SMBIZFtshHApkv9o2D8JDxb6QVvAVnwU2XN9u03Ko"
          secret        = "F7WRYALJ2viCeLNxz1-f5JHwJRzArxh5-zNS27WMouJg_AxxBYtPBHxws92FprVw3rDuyKPsNgoiwF_G3yamoA"
          redirect_uris = ["https://audiobooks.dzerv.art/auth/openid/callback"]
          realms        = ["audiobooks", "public"]
        },
        {
          id     = "EyWZe2EqeovjsJ56rcIrQBwgJRtt8aRqT2uKmhA3A"
          secret = "v5r1vRqBDFQdHr2Crth8A1JH1Uqzv6GYHRHV1iG8vlDJ6kf3d2zwKU17U1kdtVyJpsK0BLkAd4JoMezpGg"
          redirect_uris = [
            "https://cook.dzerv.art/",
            "https://cook.dzerv.art/login",
            "https://cook.dzerv.art/login?direct=1"
          ]
          origins = ["https://cook.dzerv.art"]
          realms  = ["cook"]
        },
        {
          id            = "jksU5OEyoSBBtLl1n56RYoKLj6RoFGU2i68Rf24E"
          secret        = "N6oi8didSndDDGfdPXZHKm6WQkks7LrczlnzAPQCd8MZHU9T8KY5zIJWpgLYXqQEl2OedFOcGc9fLkdBZtQ"
          redirect_uris = ["https://meals.dzerv.art/accounts/oidc/magicentry/login/callback/"]
          realms        = ["cook"]
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
      ]
    }
  })]
}
