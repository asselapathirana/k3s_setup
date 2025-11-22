#!/bin/bash
set -euo pipefail

# 1. Read nodes.txt and extract only IPs
mapfile -t IPS < <(sed 's/.*@//' nodes.txt)

# 2. Get control-plane node name(s)
CONTROL_PLANE_NODE=$(kubectl get nodes -o wide --no-headers \
    | grep Ready \
    | awk '{if ($3 ~ /control-plane/) print $1}')

# 3. Build IP → nodename map (from k8s)
declare -A NODEMAP
while read -r name ip _; do
    NODEMAP["$ip"]="$name"
done < <(kubectl get nodes -o wide --no-headers | awk '{print $1, $6}')

# 4. Label nodes based on control-plane detection
for ip in "${IPS[@]}"; do
    nodename="${NODEMAP[$ip]}"

    if [[ -z "$nodename" ]]; then
        echo "ERROR: No k8s node matches IP $ip"
        exit 1
    fi

    if [[ "$nodename" == "$CONTROL_PLANE_NODE" ]]; then
        echo "Labeling CONTROL-PLANE: $nodename"
        kubectl label node "$nodename" node-role.kubernetes.io/control-plane=true --overwrite
    else
        echo "Labeling WORKER: $nodename"
        kubectl label node "$nodename" node-role.kubernetes.io/worker=true --overwrite
    fi
done

