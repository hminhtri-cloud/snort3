# Offline topology checks: no credentials or real AWS resources required.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a"] }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  admin_cidr     = "203.0.113.10/32"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBQROvG0gt1A/7IV77PjQLGxplWazwOxqytcnZL0xFku lab-test"
}

run "lab_topology" {
  command = apply

  assert {
    condition     = length(aws_instance.lab) == 4 && length(aws_subnet.lab) == 3
    error_message = "Lab requires 4 instances across 3 subnets."
  }
  assert {
    condition = (
      aws_route.attacker_to_victim.route_table_id == aws_route_table.lab["attacker"].id &&
      aws_route.attacker_to_victim.destination_cidr_block == "10.10.3.0/24" &&
      aws_route.attacker_to_victim.network_interface_id == aws_instance.lab["gateway"].primary_network_interface_id &&
      aws_route.victim_to_attacker.route_table_id == aws_route_table.lab["victim"].id &&
      aws_route.victim_to_attacker.destination_cidr_block == "10.10.1.0/24" &&
      aws_route.victim_to_attacker.network_interface_id == aws_instance.lab["gateway"].primary_network_interface_id
    )
    error_message = "Both directions must traverse the Snort gateway ENI."
  }
  assert {
    condition = (
      !aws_instance.lab["gateway"].source_dest_check &&
      aws_instance.lab["attacker"].source_dest_check &&
      aws_instance.lab["victim"].source_dest_check &&
      aws_instance.lab["siem"].source_dest_check
    )
    error_message = "Only the forwarding gateway must disable source/destination checks."
  }
  assert {
    condition = alltrue([
      for node in aws_instance.lab :
      node.metadata_options[0].http_tokens == "required" && node.root_block_device[0].encrypted
    ])
    error_message = "Every instance requires IMDSv2 and encrypted EBS."
  }
  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.ssh_admin :
      rule.cidr_ipv4 == var.admin_cidr && rule.from_port == 22 && rule.to_port == 22
    ])
    error_message = "SSH must be limited to the administrator CIDR."
  }
  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.wazuh_agent :
      rule.cidr_ipv4 == "10.10.2.10/32"
    ])
    error_message = "Wazuh ingestion/enrollment must accept only the gateway private IP."
  }
  assert {
    condition = (
      aws_cloudwatch_log_group.snort.name == "/snort/gateway/alerts" &&
      aws_cloudwatch_log_group.snort.retention_in_days == 14 &&
      aws_instance.lab["siem"].private_ip == "10.10.2.96"
    )
    error_message = "Logging and SIEM defaults must match the project architecture."
  }
}
