resource "helm_release" "borgserver" {
  name             = "borgserver"
  namespace        = "borgserver"
  create_namespace = true
  atomic           = true

  repository = "https://dzervas.github.io/docker-borgserver/"
  chart      = "borgserver"
  version    = "1.2.6-0"

  values = [yamlencode({
    borg = {
      useKeysSecret = true
    }
    persistence = {
      storageClass = "longhorn"
      size         = "180Gi"
    }
    nodeSelector = {
      "kubernetes.io/hostname" = "gr0.dzerv.art"
    }
    clients = [
      {
        name            = "dzervas-desktop"
        restrictToPaths = ["/backup/dzervas-desktop"]
        type            = "ssh-ed25519"
        key             = "AAAAC3NzaC1lZDI1NTE5AAAAICS1ajO167YXmPzlWZT6+ydcO359SW1BljPK/GgBijHZ"
      },
      {
        name            = "dzervas-hass"
        restrictToPaths = ["/backup/dzervas-hass"]
        type            = "ssh-ed25519"
        key             = "AAAAC3NzaC1lZDI1NTE5AAAAIHYF2FfOQAsVsdR0+ya3iXiDjklWHdMAfWt31uXMz6rE"
      }
    ]
  })]
}

resource "kubernetes_manifest" "borgserver_keys_host" {
  manifest = {
    apiVersion = "bitnami.com/v1alpha1"
    kind       = "SealedSecret"
    metadata = {
      name      = "borgserver-keys-host"
      namespace = helm_release.borgserver.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      encryptedData = {
        ssh_host_ed25519_key = "AgB0i+DrX4Ar1EGgOs2Y5QM4bTkQ5zOJntHIXzZV6bzfyIx+TjK229KUcEjxEhxi2FL6H96TRz6PtC2GbNMtUYy0adMUbEn5iWpyXStxPDaaTkBKKJ+q53EHunWk50WArmqcehmd/KKIUVWy7S+/Xn7Zp1Rti4gm1jJRL4SCctpcNAaZPHGt5blpLukIhBLlJTFAkSNa2RaNB3gOTZS0RZLtGt3MXl2dkRCal3uBkvqKvBUxrH2HbUE4jgca0jCXi39jkma3BGqRgD3U9EdPkyDExkyEkDJciquGXxjuVRHFP8GTO2N0Q23zxWHrqrzIefSW2zQa6uvEOgswbkUpdgPTSDwnkHM7F+E4BKazBOKTYBpOljjY+bBz9kxxMBB5YS37wuEx/hhn68pbpssqBkV4/dTwicRpq+qAOxUlUdC/QwMlAaCjdEmK1rl7zhrz7un+/1soM4mAsUHZSC2RHoWZhVdM4gImfldO3KD/rxUdq7fPMkOipH9HzyGj3KtMurBmQ+z+Vu5kLt/qqR3Rt0b0i/Z44fbj5N36Abgu5gbP06F3gjXbX+9IxYdv80J8xwRQ/N7KKn6nhZcaAbaDIuFMRIFqy2q3kIvD/gO/ZBsiuXYo1vGFNzAJIY9JZTi/hQeRzPOugEP5ixbmZXX66gNLlgsmqHJF/Zrt09+u5T0rMUssD9ZDNl4P3U6/y1PqZlDT/8oDqJGlkBtm/N4BM8/dhBZpCLqVzFVDresy0Tb58D46eNvkrfixjPKXNQ2LCn/6R8LxAjGz6Dgb3DPyVSQKjD+mvgl6u67uaGuAetkUTkVtlPp1JvfhLG3p+K9ZIjxKH8vBXJ4cl1eYxGkL+bpN202sNj0PqT4yv5i/CenvXJHyCFH6a6XnCK8L2cjPF+O60mk4+jVqfRzIC/JXwCmfjgXbOwiYdqphuud6qVP0tdGBosAMKZCxU13UrvenZvSKZyIZo0asM5kcax2H15v/RNnbGkFBQ0Z8dSVDiaTOF3sINGTaHqx+ICOtDYrW7HZ1PYON5OiSuvPDtHmmbCdEa+KZ2p28zAF9RSiwhmeoPVEJPie/Nq7GcVBNT+XejZzhmfrGgt8DAW5tx4s5a+UwpVZVhdQVcoHsop0o6JI+Dzyl+xwlVg3WmiL5RoBXOkvmN6nZfsFT3Q0wEJGbuEBKLMPrx954mUdrH0yjFdnj7HtTwm+yXf3AXWjPQibwvVPhVAzDKR4lJpMuT2mWMMMNx53Q6vbiknpofJ4="
        ssh_host_rsa_key     = "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"
      }
      template = {
        metadata = {
          name      = "borgserver-keys-host"
          namespace = helm_release.borgserver.namespace
        }
      }
    }
  }
}
