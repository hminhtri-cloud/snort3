output "instances" {
  value = {
    for role, instance in aws_instance.lab : role => {
      id         = instance.id
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
      ssh        = "ssh -i /path/to/private-key ubuntu@${instance.public_ip}"
    }
  }
}

output "wazuh_ssh_tunnel" {
  value = "ssh -i /path/to/private-key -N -L 8443:127.0.0.1:443 ubuntu@${aws_instance.lab["siem"].public_ip}"
}

output "wazuh_dashboard_url" {
  value = "https://localhost:8443 (sau khi mở SSH tunnel; mật khẩu lấy trên SIEM theo README)"
}

output "cloudwatch_logs_command" {
  value = "aws logs tail '${aws_cloudwatch_log_group.snort.name}' --region ${var.aws_region} --since 30m --follow"
}

output "cloudwatch_log_stream" {
  value = aws_instance.lab["gateway"].id
}

output "vpc_id" {
  value = aws_vpc.lab.id
}

output "ami_id" {
  value = coalesce(var.ubuntu_ami_id, data.aws_ami.ubuntu.id)
}
