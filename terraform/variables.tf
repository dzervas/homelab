variable "key_pair" {
	type = string
	description = "Key Pair used to create instances"
	default = "default"
}

variable "domain" {
	type = string
	description = "Main domain name to use - Needs a dot at the end!"
	default = "server.lan."
}

variable "email" {
	type = string
	description = "E-Mail to use for domain creation"
	default = "admin@server.lan"
}
