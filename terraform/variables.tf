variable "aws_region" {
  description = "AWS Region triển khai lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "snort3-lab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.project_name))
    error_message = "Tên project dài 3–30 ký tự: chữ thường, số và dấu gạch ngang."
  }
}

variable "availability_zone" {
  description = "Để null để tự chọn một AZ khả dụng; cả lab ở cùng AZ."
  type        = string
  default     = null
}

variable "admin_cidr" {
  description = "Public IPv4/CIDR của bạn, ví dụ 203.0.113.10/32, được SSH vào lab."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && try(tonumber(split("/", var.admin_cidr)[1]) >= 24, false)
    error_message = "Nhập IPv4 CIDR /24 hoặc hẹp hơn; nên dùng IP hiện tại /32."
  }
}

variable "ssh_public_key" {
  description = "Nội dung public key OpenSSH; không nhập private key."
  type        = string
  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) [A-Za-z0-9+/=]+( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "Cần public key ssh-ed25519 hoặc ssh-rsa hợp lệ."
  }
}

variable "ubuntu_ami_id" {
  description = "Override AMI Ubuntu 24.04 amd64, hoặc null để dùng AMI Canonical mới nhất."
  type        = string
  default     = null
}

variable "instance_types" {
  description = "Chỉ dùng instance x86_64. SIEM cần tối thiểu 4 vCPU/8 GiB theo Wazuh quickstart."
  type = object({
    attacker = string
    gateway  = string
    victim   = string
    siem     = string
  })
  default = {
    attacker = "t3.micro"
    gateway  = "t3.medium"
    victim   = "t3.micro"
    siem     = "c6i.xlarge"
  }
}

variable "snort_version" {
  type    = string
  default = "3.12.2.0"
  validation {
    condition     = can(regex("^3\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.snort_version))
    error_message = "Phiên bản Snort dạng 3.x.y.z."
  }
}

variable "daq_version" {
  type    = string
  default = "3.0.27"
  validation {
    condition     = can(regex("^3\\.[0-9]+\\.[0-9]+$", var.daq_version))
    error_message = "Phiên bản libDAQ dạng 3.x.y."
  }
}

variable "log_group_name" {
  description = "Nếu tên này đã có trong account/Region, import trước khi apply hoặc đổi tên."
  type        = string
  default     = "/snort/gateway/alerts"
  validation {
    condition     = can(regex("^[A-Za-z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "Tên CloudWatch log group không hợp lệ."
  }
}

variable "log_retention_days" {
  type    = number
  default = 14
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Chọn retention CloudWatch được hỗ trợ (1–365 ngày trong lab này)."
  }
}
