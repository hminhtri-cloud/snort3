# Snort 3 IDS + CloudWatch Logs + Wazuh SIEM trên AWS

Bộ Terraform triển khai một lab mới, gồm mạng và tự cài phần mềm qua EC2 user-data/cloud-init.

## 1. Kiến trúc

```text
VPC 10.10.0.0/16 — một Availability Zone

Attacker 10.10.1.10  ──►  Snort Gateway 10.10.2.10  ──►  Victim 10.10.3.10
Ubuntu + nmap             AFPacket passive IDS          nginx :80, /admin
subnet 10.10.1.0/24        subnet 10.10.2.0/24             subnet 10.10.3.0/24
                         │                 ▲
                         │                 │ log/agent 1514, enrollment 1515
                         ├── CloudWatch    Wazuh SIEM 10.10.2.96
                         │   /snort/       Manager + Indexer + Dashboard
                         │   gateway/alerts
                         └── Wazuh Agent

Máy cá nhân ── SSH tunnel ──► SIEM:443 ──► https://localhost:8443
```

Các thành phần:

- VPC, Internet Gateway, 3 subnet và 3 route table.
- Route `10.10.3.0/24 → Gateway ENI` tại subnet Attacker; route ngược `10.10.1.0/24 → Gateway ENI` tại subnet Victim. Hai route cụ thể hơn VPC local `/16` nên buộc **cả hai chiều** đi qua Snort.
- Gateway một ENI, `source_dest_check = false`, IPv4 forwarding bật, tắt reverse-path filtering và ICMP redirects. Không NAT nguồn traffic lab.
- 4 EC2 Ubuntu **24.04 LTS amd64**, IMDSv2 bắt buộc, EBS gp3 mã hóa; IAM instance profiles riêng, SSM trên cả 4 máy.
- Biên dịch **Snort 3.12.2.0 + libDAQ 3.0.27** từ source; cấu hình AFPacket **passive**; không drop traffic.
- 3 rule Snort: ICMP echo `1000001`, TCP SYN `1000002`, HTTP URI chứa `/admin` `1000003`.
- `snort.service`, log `/var/log/snort/alert_fast.txt`, logrotate.
- CloudWatch Agent gửi alert tới log group `/snort/gateway/alerts`, stream là EC2 instance ID của Gateway; retention mặc định 14 ngày; metric filter và dashboard CloudWatch.
- Wazuh **4.14.x** all-in-one dùng installer chính thức; Agent lấy bản patch mới nhất trong cùng nhánh 4.14. Không pin đúng 4.14.9 trong báo cáo cũ; bản thực tế được ghi trong log cài đặt/package manager.
- Decoder/rule Wazuh riêng cho 3 SID demo, rule IDs `110001`, `110002`, `110003`. Builtin decoder Snort 2 được exclude để tránh tranh chấp định dạng với decoder lab.

**Mô hình kết nối Internet:** cả 4 máy có public IPv4 để tải package và dùng SSM, không cần NAT Gateway/VPC endpoints. Đây không phải mô hình private-subnet. SG chỉ mở SSH từ `admin_cidr`; các cổng demo Victim và Wazuh ingestion chỉ nhận traffic từ private IP/subnet tương ứng. Port 443 Dashboard, 9200 Indexer và 55000 API không mở public; Dashboard đi qua tunnel. Không có EIP: public IP có thể đổi sau stop/start, xem lại `terraform output` sau refresh.

## 2. Cấu trúc thư mục

```text
terraform/
├── versions.tf             # Terraform/provider
├── variables.tf            # Biến đầu vào
├── network.tf              # VPC/subnet/routes hai chiều
├── security.tf             # Security groups
├── iam.tf                  # Instance profiles + quyền CloudWatch giới hạn
├── compute.tf              # EC2, AMI, gzip user-data
├── monitoring.tf           # Log group, metric filter, dashboard
├── outputs.tf
├── terraform.tfvars.example
├── templates/              # Bootstrap từng vai trò
├── tests/lab.tftest.hcl     # Mock AWS topology tests
└── scripts/check_templates.py
```

## 3. Chuẩn bị

Trên máy cá nhân:

- Terraform >= 1.7 và < 2.0, AWS CLI v2; Python 3 để chạy kiểm tra template.
- AWS credentials đang hoạt động qua profile/SSO hoặc cơ chế đăng nhập đang dùng.
- Quyền tạo EC2/VPC/SG/key pair, IAM roles/policies/instance profiles và `iam:PassRole`, CloudWatch Logs/metrics/dashboard. Không đặt access key trong file Terraform.
- Một cặp SSH key; Terraform chỉ nhận **public key**, private key giữ trên máy bạn.

```bash
cd /Users/huynhminhtri/project/snort3/terraform
aws sts get-caller-identity
cp terraform.tfvars.example terraform.tfvars
```

Sửa `terraform.tfvars`:

```hcl
admin_cidr = "YOUR_PUBLIC_IP/32"
ssh_public_key = "ssh-ed25519 AAAA... your-key-comment"
```

Lấy public IP bằng `curl -4 https://checkip.amazonaws.com`. Dán nội dung public key, ví dụ file `~/.ssh/id_ed25519.pub`, vào `ssh_public_key`. Nếu dùng key PEM cũ, có thể xuất public key bằng `ssh-keygen -y -f /path/to/key.pem`.

Chọn profile khi cần:

```bash
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
```

`aws_region` trong tfvars quyết định Region của Terraform. Không cần giữ profile trong mã nguồn.

### Log group từ lab cũ đã tồn tại

Lab trước đã có `/snort/gateway/alerts`. Chọn **một** cách:

1. Giữ log group cũ: sau `terraform init`, import để Terraform quản lý retention và vòng đời của log group đó:

   ```bash
   terraform import aws_cloudwatch_log_group.snort /snort/gateway/alerts
   ```

   Khi chạy `terraform destroy`, log group đã import và log cũ trong đó cũng bị xóa.

2. Muốn tách hẳn log lab mới: đổi trong tfvars:

   ```hcl
   log_group_name = "/snort/terraform/gateway/alerts"
   ```

Các EC2/VPC được tạo mới, không tự import EC2/VPC cũ. Dải `10.10.0.0/16` có thể dùng trong một VPC độc lập. Không gắn peering với VPC trùng CIDR.

## 4. Khởi tạo, kiểm tra và triển khai

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
python3 scripts/check_templates.py
terraform plan -out=lab.tfplan
terraform apply lab.tfplan
terraform output
```

`terraform test` dùng **mock AWS provider**, không tạo tài nguyên AWS. `plan/apply` thật sử dụng credentials của bạn. Terraform state mặc định lưu local; `.gitignore` loại state/tfvars/plan khỏi Git. Commit `.terraform.lock.hcl` để khóa provider.

`terraform apply` hoàn tất tạo EC2 **không đồng nghĩa cloud-init đã cài xong**. Snort phải biên dịch source; SIEM phải cài Indexer/Manager/Dashboard nên cần chờ thêm, có thể hàng chục phút tùy tốc độ tải và CPU credits. Các T3 dùng credit mode `standard`; khi thiếu credit, cài đặt có thể chậm.

Lấy SSH IP bằng `terraform output instances`. Trên **từng máy**:

```bash
sudo cloud-init status --wait
sudo test -f /var/lib/snort-lab-bootstrap.done && echo 'Bootstrap complete'
sudo less /var/log/snort-lab-bootstrap.log
```

Nếu lỗi, có marker `/var/lib/snort-lab-bootstrap.failed`; xem thêm `/var/log/cloud-init-output.log`. Không dùng `set -x` khi xử lý log Wazuh vì installer chứa mật khẩu.

Sau khi sửa template, `terraform plan` sẽ thể hiện thay thế EC2 vì `user_data_replace_on_change = true`. Để tạo lại riêng máy bị lỗi bootstrap:

```bash
terraform apply -replace='aws_instance.lab["gateway"]'
```

Thay `gateway` bằng vai trò cần tạo lại. Nếu tạo lại SIEM, các agent key cũ không còn hợp lệ: tạo lại Gateway hoặc enroll lại Agent. Nếu tạo lại Gateway, xóa entry `snort-gateway` cũ trên Wazuh trước khi enroll lại nếu gặp lỗi tên agent trùng.

## 5. Kiểm tra Snort và đường đi traffic

Trên **Gateway**:

```bash
sudo systemctl status snort --no-pager
sudo /usr/local/bin/snort -V
sudo /usr/local/bin/snort -T -c /usr/local/etc/snort/snort.lua
sysctl net.ipv4.ip_forward
ip -4 route
sudo tcpdump -ni any host 10.10.1.10 and host 10.10.3.10
```

Tên interface được phát hiện tự động (`enX0`, `ens5` hoặc `eth0` tùy AMI), không cần sửa code theo báo cáo cũ. Do router một ENI, tcpdump có thể thấy bản vào/ra của cùng gói tin và số alert có thể lặp. Đánh giá theo SID/traffic, không coi số alert là số request duy nhất.

Trên **Attacker**, sau khi bootstrap của cả lab đã xong:

```bash
snort-lab-demo
```

Hoặc chạy lần lượt:

```bash
ping -c 4 10.10.3.10
sudo nmap -n -Pn -sS -p 1-100 10.10.3.10
curl --noproxy '*' http://10.10.3.10/admin
curl --noproxy '*' http://10.10.3.10/
```

Trên **Gateway**:

```bash
sudo tail -f /var/log/snort/alert_fast.txt
```

Kỳ vọng có SID `1000001`, `1000002`, `1000003`. HTTP `/admin` vẫn trả `200`: Snort đang ở chế độ passive IDS. Rule TCP SYN đánh dấu **mọi SYN** từ Attacker đến Victim, bao gồm kết nối curl bình thường; đây là rule quan sát SYN demo, chưa phải thuật toán phân biệt port scan với traffic hợp lệ. Rule `/admin` phát hiện URI chứa chuỗi, không xác nhận việc truy cập đó là một cuộc tấn công.

## 6. Kiểm tra CloudWatch Logs

Trên **máy cá nhân** đã đăng nhập AWS:

```bash
aws logs describe-log-streams \
  --region us-east-1 \
  --log-group-name /snort/gateway/alerts \
  --order-by LastEventTime --descending --max-items 5

aws logs tail /snort/gateway/alerts \
  --region us-east-1 --since 30m --follow
```

Nếu đổi log group/Region, dùng lệnh đúng từ `terraform output -raw cloudwatch_logs_command`. CloudWatch Console → Logs → Log groups → log group → stream là **ID EC2 Gateway mới**, không phải `i-0ddad498adb5c2a26` của lab cũ.

Dashboard CloudWatch có tên bằng `project_name`, mặc định `snort3-lab`. Metric `SnortAlerts` đếm dòng chứa `LAB` sau lúc tạo metric filter; không backfill alert cũ.

Nếu log local đã có mà CloudWatch chưa có, trên Gateway:

```bash
sudo systemctl status amazon-cloudwatch-agent --no-pager
sudo less /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

Quyền instance profile của Gateway chỉ tạo stream/ghi/describe stream trong log group được quản lý. Nó không có quyền xem mọi log group hay tail log; các lệnh đọc bên trên nên chạy bằng AWS identity trên máy cá nhân.

## 7. Kiểm tra Wazuh

Trên **SIEM**, đợi cloud-init hoàn tất rồi kiểm tra:

```bash
sudo systemctl status wazuh-manager wazuh-indexer wazuh-dashboard filebeat --no-pager
sudo /var/ossec/bin/agent_control -lc
sudo less /var/ossec/logs/ossec.log
```

Trên **Gateway**:

```bash
sudo systemctl status wazuh-agent --no-pager
sudo less /var/ossec/logs/ossec.log
```

Agent tự enroll qua `10.10.2.96:1515/tcp`, gửi event qua `1514/tcp` và retry nếu Manager chưa sẵn sàng. Có thể restart `sudo systemctl restart wazuh-agent` sau khi SIEM sẵn sàng để kích hoạt lại kết nối.

### Mở Dashboard qua SSH tunnel

Trên **máy cá nhân**, lấy câu lệnh mẫu:

```bash
terraform output -raw wazuh_ssh_tunnel
```

Thay `/path/to/private-key` bằng private key tương ứng public key đã khai báo, ví dụ:

```bash
ssh -i ~/.ssh/id_ed25519 -N -L 8443:127.0.0.1:443 ubuntu@SIEM_PUBLIC_IP
```

Mở **https://localhost:8443**. Wazuh dùng chứng chỉ tự ký của lab nên trình duyệt yêu cầu xác nhận chứng chỉ. Username là `admin`. Lấy mật khẩu trên **SIEM**:

```bash
sudo tar -xOf /root/wazuh-install/wazuh-install-files.tar \
  wazuh-install-files/wazuh-passwords.txt
```

Tìm block `admin`. File/archive và log installer được giữ root-only trên SIEM; Terraform output/state không chứa mật khẩu được installer sinh ra.

Dashboard → Agents: chờ `snort-gateway` chuyển Active. Chạy demo mới từ Attacker sau khi Agent Active, rồi vào Threat hunting/Security events, lọc:

```text
rule.groups: snort3_lab
```

Hoặc lọc theo `rule.id` là `110001`, `110002`, `110003`. Chọn time range phù hợp (ví dụ Last 15 minutes).

Để kiểm tra riêng decoder/rule, trên **SIEM**:

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Dán nguyên một dòng từ `alert_fast.txt`; Phase 2 cần nhận decoder `snort3-lab`, Phase 3 nhận rule ID tương ứng. Xem raw alert JSON tại `/var/ossec/logs/alerts/alerts.json` nếu UI chưa hiển thị.

## 8. Chi phí và dọn tài nguyên

Mặc định: Attacker/Victim `t3.micro`, Gateway `t3.medium`, SIEM `c6i.xlarge` (4 vCPU/8 GiB), tổng EBS 122 GiB. Phát sinh phí EC2, EBS, public IPv4, CloudWatch Logs, custom metric/dashboard và truy vấn Logs Insights theo sử dụng. Không tạo NAT Gateway. Có thể đổi `instance_types`, nhưng AMI/build này cần x86_64; SIEM phải đủ tài nguyên để cài all-in-one.

Dọn toàn bộ tài nguyên do module quản lý:

```bash
terraform plan -destroy
terraform destroy
```

Destroy xóa cả EBS và CloudWatch log group được quản lý (kể cả log group đã import). Các tài nguyên lab cũ chưa import không thuộc state này.

## 9. Tham khảo

- Snort: https://docs.snort.org/ ; source https://github.com/snort3/snort3
- libDAQ: https://github.com/snort3/libdaq
- Wazuh quickstart, OS và sizing: https://documentation.wazuh.com/current/quickstart.html
- Wazuh custom decoders: https://documentation.wazuh.com/current/user-manual/ruleset/decoders/custom.html
- VPC middlebox routing: https://docs.aws.amazon.com/vpc/latest/userguide/route-table-options.html
- CloudWatch Agent: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html

Các kiểm tra offline xác nhận cấu trúc Terraform và template; xác nhận biên dịch/cài đặt, forwarding thực tế, log lên CloudWatch và Agent Active cần `plan/apply` thật và các bước kiểm tra runtime ở trên.
