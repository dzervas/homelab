resource "kubernetes_manifest" "minecraft_snapshot_task" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "minecraft-snpashot"
      namespace = var.longhorn_namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      name        = "minecraft-snapshot"
      cron        = "0 10 * * *" # At 10:00 AM every day
      task        = "snapshot"
      retain      = 14 # 2 Weeks
      concurrency = 1
      groups      = ["minecraft"]
      labels = {
        managed_by = "terraform"
      }
    }
  }
}
