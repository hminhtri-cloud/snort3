resource "aws_security_group" "node" {
  for_each    = local.nodes
  name_prefix = "${var.project_name}-${each.key}-"
  description = "${each.key} lab security group"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.project_name}-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  for_each          = local.nodes
  security_group_id = aws_security_group.node[each.key].id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH from administrator"
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  for_each          = local.nodes
  security_group_id = aws_security_group.node[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Package repositories, SSM and lab traffic"
}

# CIDR rules are intentional: SG references do not identify original sources
# through a middlebox. Gateway sees forwarded packets from both lab subnets.
resource "aws_vpc_security_group_ingress_rule" "gateway_transit" {
  for_each          = toset([local.subnets.attacker, local.subnets.victim])
  security_group_id = aws_security_group.node["gateway"].id
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
  description       = "Lab transit through Snort"
}

resource "aws_vpc_security_group_ingress_rule" "victim_lab" {
  security_group_id = aws_security_group.node["victim"].id
  cidr_ipv4         = "${local.nodes.attacker.ip}/32"
  ip_protocol       = "-1"
  description       = "ICMP, SYN scan and HTTP from lab attacker only"
}

resource "aws_vpc_security_group_ingress_rule" "attacker_return" {
  security_group_id = aws_security_group.node["attacker"].id
  cidr_ipv4         = "${local.nodes.victim.ip}/32"
  ip_protocol       = "-1"
  description       = "Return traffic via middlebox, including ICMP errors"
}

resource "aws_vpc_security_group_ingress_rule" "wazuh_agent" {
  for_each          = toset(["1514", "1515"])
  security_group_id = aws_security_group.node["siem"].id
  cidr_ipv4         = "${local.nodes.gateway.ip}/32"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "Wazuh event channel and enrollment from Snort gateway"
}

# Dashboard 443 is accessed through an SSH local-forward on the SIEM host.
# Indexer 9200 and API 55000 are never exposed in security groups.
