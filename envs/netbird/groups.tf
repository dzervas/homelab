data "netbird_group" "all" {
  name = "All"
}

resource "netbird_group" "kubernetes" {
  name = "kubernetes"
}

resource "netbird_group" "guest" {
  name = "guest"
}
