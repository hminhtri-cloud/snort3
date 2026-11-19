#!/usr/bin/env python3
"""Render real Terraform templates and check embedded Bash/Python/JSON/XML.

Local checks only. Never runs bootstrap commands or calls AWS APIs.
Requires terraform init first. Run from this module's directory.
"""

import ast
import base64
import gzip
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
EXPRESSION = r'''jsonencode({for node in ["attacker", "gateway", "victim", "siem"] : node => templatefile("${path.module}/templates/${node}.sh.tftpl", {
common = file("${path.module}/templates/common.sh"),
attacker_ip = "10.10.1.10", victim_ip = "10.10.3.10", siem_ip = "10.10.2.96",
snort_version = "3.12.2.0", daq_version = "3.0.27", aws_region = "us-east-1",
log_group_json = jsonencode("/snort/gateway/alerts")
})})'''
# terraform console reads one expression per physical input line.
result = subprocess.run(
    [
        "terraform", "console", "-no-color",
        "-var=admin_cidr=203.0.113.10/32",
        "-var=ssh_public_key=ssh-ed25519 AAAA test",
    ],
    input=" ".join(EXPRESSION.splitlines()) + "\n",
    cwd=ROOT, text=True, capture_output=True, check=True,
)
scripts = json.loads(json.loads(result.stdout))

for node, script in scripts.items():
    subprocess.run(["bash", "-n"], input=script, text=True, check=True)
    # gzip user-data must fit EC2's 16 KiB decoded payload limit.
    compressed = gzip.compress(script.encode())
    assert len(compressed) <= 16384, (node, len(compressed))
    assert gzip.decompress(base64.b64decode(base64.b64encode(compressed))).decode() == script
    assert script.startswith("#!/bin/bash\n")
    assert "touch /var/lib/snort-lab-bootstrap.done" in script
    for body in re.findall(r"python3 - <<'PY'\n(.*?)\nPY", script, re.S):
        ast.parse(body)
    for body in re.findall(r"<<'CW'\n(.*?)\nCW", script, re.S):
        config = json.loads(body)
        entry = config["logs"]["logs_collected"]["files"]["collect_list"][0]
        assert entry["log_group_name"] == "/snort/gateway/alerts"
        assert entry["file_path"] == "/var/log/snort/alert_fast.txt"
    for marker in ("DECODER", "RULES") if node == "siem" else ():
        body = re.search(r"<<'" + marker + r"'\n(.*?)\n" + marker, script, re.S).group(1)
        ET.fromstring(body)
    print(f"{node}: Bash/heredocs OK; gzip user-data {len(compressed)} bytes")

gateway = scripts["gateway"]
assert "--daq-mode passive" in gateway
assert "net.ipv4.ip_forward = 1" in gateway
assert "MASQUERADE" not in gateway
for sid in (1000001, 1000002, 1000003):
    assert f"sid:{sid};" in gateway
print("Template checks passed. Runtime installation still requires a real AWS deployment.")
