#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Usage:
#   ./bootstrap_vm.sh <password> <user@host> [public_key_file]
#
# Example:
#   ./bootstrap_vm.sh mypass user@192.168.6.121
# ---------------------------------------------------------

PASS=${1:-}
HOST=${2:-}
PUBKEY_FILE=${3:-$HOME/.ssh/id_rsa.pub}

if [[ -z "$PASS" || -z "$HOST" ]]; then
    echo "Usage: $0 <password> <user@host> [pubkey]"
    exit 1
fi

if [[ ! -f "$PUBKEY_FILE" ]]; then
    echo "Public key not found: $PUBKEY_FILE"
    exit 1
fi

REMOTE_USER="${HOST%@*}"
REMOTE_IP="${HOST#*@}"

echo ">>> Bootstrapping $HOST"
echo ">>> Using key: $PUBKEY_FILE"
echo "-----------------------------------------------------"

# ---------------------------------------------------------
# 1) Initial setup on remote as default user
# ---------------------------------------------------------
ssh "$HOST" bash -s <<EOF
set -euo pipefail

echo ">>> Creating user 'assela'..."
if ! id -u assela >/dev/null 2>&1; then
    echo "$PASS" | sudo -S adduser --disabled-password --gecos "" assela
fi
echo ">>> Set password for user 'assela'..."
echo "$PASS" | sudo -S bash -c 'echo "assela:$PASS" | chpasswd'
echo ">>> Adding 'assela' to sudo group..."
echo "$PASS" | sudo -S usermod -aG sudo assela

echo ">>> Adding TEMPORARY NOPASSWD sudo for 'assela'..."
echo "$PASS" | sudo -S bash -c 'echo "assela ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/00-assela-temp'
echo "$PASS" | sudo -S chmod 440 /etc/sudoers.d/00-assela-temp

EOF

# ---------------------------------------------------------
# 2) Copy SSH key to assela
# ---------------------------------------------------------
echo ">>> Copying SSH key to assela@$REMOTE_IP..."
ssh-copy-id -i "$PUBKEY_FILE" "assela@$REMOTE_IP"

# ---------------------------------------------------------
# 3) Final provisioning as assela
# ---------------------------------------------------------
ssh "assela@$REMOTE_IP" bash -s <<EOF
set -euo pipefail

echo ">>> Installing permanent NOPASSWD sudo..."
sudo bash -c 'echo "assela ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/99-assela'
sudo chmod 440 /etc/sudoers.d/99-assela

echo ">>> Removing temporary sudo file..."
sudo rm -f /etc/sudoers.d/00-assela-temp

DEFAULT_USER="$REMOTE_USER"
if id -u "\$DEFAULT_USER" >/dev/null 2>&1; then
    echo ">>> Removing default user '\$DEFAULT_USER'..."
    sudo deluser --remove-home "\$DEFAULT_USER" || true
fi

echo ">>> Disabling password login..."
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

echo ">>> Bootstrap complete!"
EOF

echo "-----------------------------------------------------"
echo ">>> Finished. Login with:"
echo "    ssh assela@$REMOTE_IP"
echo "-----------------------------------------------------"

