data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "admin" {
  key_name_prefix = "${var.project_name}-"
  public_key      = trimspace(var.ssh_public_key)
}

resource "aws_instance" "lab" {
  for_each                    = local.nodes
  ami                         = coalesce(var.ubuntu_ami_id, data.aws_ami.ubuntu.id)
  instance_type               = var.instance_types[each.key]
  subnet_id                   = aws_subnet.lab[each.value.subnet].id
  private_ip                  = each.value.ip
  associate_public_ip_address = true
  key_name                    = aws_key_pair.admin.key_name
  vpc_security_group_ids      = [aws_security_group.node[each.key].id]
  iam_instance_profile        = aws_iam_instance_profile.node[each.key].name
  source_dest_check           = each.key != "gateway"
  user_data_replace_on_change = true

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/${each.key}.sh.tftpl", {
    common         = file("${path.module}/templates/common.sh")
    attacker_ip    = local.nodes.attacker.ip
    victim_ip      = local.nodes.victim.ip
    siem_ip        = local.nodes.siem.ip
    snort_version  = var.snort_version
    daq_version    = var.daq_version
    aws_region     = var.aws_region
    log_group_json = jsonencode(var.log_group_name)
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.disk
    encrypted             = true
    delete_on_termination = true
  }

  dynamic "credit_specification" {
    for_each = startswith(var.instance_types[each.key], "t") ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }

  tags = { Name = "${var.project_name}-${each.key}", Role = each.key }

  # Internet and SGs must be ready before cloud-init downloads packages.
  # Do not depend on transit routes: they depend on the gateway ENI above.
  depends_on = [
    aws_route.internet,
    aws_route_table_association.lab,
    aws_vpc_security_group_egress_rule.outbound,
    aws_vpc_security_group_ingress_rule.wazuh_agent,
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy.gateway_logs,
  ]
}
