resource "aws_vpc" "network" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    managed_by = "terraform"
  }
}

resource "aws_internet_gateway" "network" {
  vpc_id = aws_vpc.network.id

  tags = {
    managed_by = "terraform"
  }
}

resource "aws_subnet" "network" {
  vpc_id                  = aws_vpc.network.id
  cidr_block              = aws_vpc.network.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    managed_by = "terraform"
  }
}

resource "aws_route_table" "network" {
  vpc_id = aws_vpc.network.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.network.id
  }

  tags = {
    managed_by = "terraform"
  }
}

resource "aws_route_table_association" "network" {
  subnet_id      = aws_subnet.network.id
  route_table_id = aws_route_table.network.id
}
