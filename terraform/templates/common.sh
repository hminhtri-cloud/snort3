# Shared cloud-init prologue, inserted by templatefile().
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /var/log/snort-lab-bootstrap.log) 2>&1
trap 'touch /var/lib/snort-lab-bootstrap.failed; echo "Bootstrap failed at line $LINENO"' ERR
rm -f /var/lib/snort-lab-bootstrap.failed /var/lib/snort-lab-bootstrap.done

retry() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if "$@"; then return 0; fi
        sleep 15
    done
    return 1
}

retry apt-get -o DPkg::Lock::Timeout=300 update
retry apt-get -o DPkg::Lock::Timeout=300 install -y ca-certificates curl gnupg python3 tcpdump

# Canonical AWS AMIs normally ship this snap already.
if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
    retry snap install amazon-ssm-agent --classic
fi
snap start --enable amazon-ssm-agent
