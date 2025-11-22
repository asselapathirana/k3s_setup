#!/usr/bin/env bash
set -euo pipefail

NODES_FILE="${1:-nodes.txt}"

if [[ ! -f "$NODES_FILE" ]]; then
  echo "Nodes file '$NODES_FILE' not found."
  exit 1
fi

mapfile -t NODES < "$NODES_FILE"

if [[ "${#NODES[@]}" -lt 1 ]]; then
  echo "Nodes file is empty."
  exit 1
fi

CONTROL="${NODES[0]}"
WORKERS=("${NODES[@]:1}")

echo "Control-plane: $CONTROL"
echo "Workers: ${WORKERS[*]:-<none>}"
echo

set -x
# Install K3s server on control-plane
echo ">>> Installing K3s server on $CONTROL"
ssh "$CONTROL" "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --write-kubeconfig-mode=644' sh -"

# Get cluster token and server IP
echo ">>> Getting K3s node token from control-plane"
TOKEN=$(ssh "$CONTROL" "sudo cat /var/lib/rancher/k3s/server/node-token")

echo ">>> Detecting control-plane IP"
SERVER_IP=$(ssh "$CONTROL" "hostname -I | awk '{print \$1}'")
if [[ -z "$SERVER_IP" ]]; then
  echo "Could not detect control-plane IP."
  exit 1
fi
echo "Control-plane API IP: $SERVER_IP"

# Install K3s agents on workers
for W in "${WORKERS[@]}"; do
  echo ">>> Installing K3s agent on $W"
  ssh "$W" "curl -sfL https://get.k3s.io | \
    K3S_URL='https://$SERVER_IP:6443' \
    K3S_TOKEN='$TOKEN' \
    sh -"
done

# Fetch kubeconfig locally
echo ">>> Fetching kubeconfig from control-plane"
ssh "$CONTROL" "sudo cat /etc/rancher/k3s/k3s.yaml" > k3s.yaml

# Patch API server address from 127.0.0.1 to actual IP
sed -i "s/127.0.0.1/$SERVER_IP/" k3s.yaml

