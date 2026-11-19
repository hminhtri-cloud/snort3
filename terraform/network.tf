locals {
  az = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])
  subnets = {
    attacker = "10.10.1.0/24"
    gateway  = "10.10.2.0/24"
    victim   = "10.10.3.0/24"
  }
  nodes = {
    attacker = { subnet = "attacker", ip = "10.10.1.10", disk = 16 }
    gateway  = { subnet = "gateway", ip = "10.10.2.10", disk = 30 }
    victim   = { subnet = "victim", ip = "10.10.3.10", disk = 16 }
    siem     = { subnet = "gateway", ip = "10.10.2.96", disk = 60 }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "lab" {
  for_each                = local.subnets
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = each.value
  availability_zone       = local.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-${each.key}" }
}

resource "aws_route_table" "lab" {
  for_each = local.subnets
  vpc_id   = aws_vpc.lab.id
  tags     = { Name = "${var.project_name}-${each.key}" }
}

resource "aws_route" "internet" {
  for_each               = local.subnets
  route_table_id         = aws_route_table.lab[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "lab" {
  for_each       = local.subnets
  subnet_id      = aws_subnet.lab[each.key].id
  route_table_id = aws_route_table.lab[each.key].id
}

# More-specific routes override the VPC local /16 route in BOTH directions.
# No NAT: Snort and the victim retain the attacker's original 10.10.1.10 source.
resource "aws_route" "attacker_to_victim" {
  route_table_id         = aws_route_table.lab["attacker"].id
  destination_cidr_block = local.subnets.victim
  network_interface_id   = aws_instance.lab["gateway"].primary_network_interface_id
}

resource "aws_route" "victim_to_attacker" {
  route_table_id         = aws_route_table.lab["victim"].id
  destination_cidr_block = local.subnets.attacker
  network_interface_id   = aws_instance.lab["gateway"].primary_network_interface_id
}
