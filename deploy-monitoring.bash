#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   export DOMAIN_NAME=example.com
#   export GRAFANA_ADMIN_PASSWORD='SomeStrongPassword123!'
#   # optional: export GRAFANA_ADMIN_USER='admin'
#   ./deploy-monitoring.sh
#
# This will:
#   - create the "monitoring" namespace if missing
#   - create the "grafana-admin" secret if missing
#   - render monitoring-values.yaml from monitoring-values.yaml.tpl
#   - install/upgrade kube-prometheus-stack via Helm

NAMESPACE="monitoring"
VALUES_TEMPLATE="monitoring-values.yaml.tpl"
VALUES_RENDERED="monitoring-values.yaml"
RELEASE_NAME="kube-prometheus-stack"
GRAFANA_SECRET_NAME="grafana-admin"
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not installed"; exit 1; }
# Require DOMAIN_NAME
: "${DOMAIN_NAME:?Please set DOMAIN_NAME, e.g. export DOMAIN_NAME=example.com}"

# Default admin user if not provided
: "${GRAFANA_ADMIN_USER:=admin}"

echo ">>> Using DOMAIN_NAME=${DOMAIN_NAME}"
echo ">>> Grafana admin user: ${GRAFANA_ADMIN_USER}"

# Ensure namespace exists
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo ">>> Creating namespace ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
else
  echo ">>> Namespace ${NAMESPACE} already exists"
fi

# Ensure Grafana admin secret exists
if ! kubectl get secret "${GRAFANA_SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo ">>> Grafana admin secret '${GRAFANA_SECRET_NAME}' not found in namespace ${NAMESPACE}"

  # Require password only if we need to create the secret
  : "${GRAFANA_ADMIN_PASSWORD:?Please set GRAFANA_ADMIN_PASSWORD for Grafana admin}"

  echo ">>> Creating secret ${GRAFANA_SECRET_NAME} in namespace ${NAMESPACE}"
  kubectl create secret generic "${GRAFANA_SECRET_NAME}" \
    -n "${NAMESPACE}" \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER}" \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}"
else
  echo ">>> Grafana admin secret '${GRAFANA_SECRET_NAME}' already exists in ${NAMESPACE}, not touching it"
fi

# Check for envsubst
if ! command -v envsubst >/dev/null 2>&1; then
  echo "ERROR: envsubst not found. Install 'gettext' (on Debian/Ubuntu: sudo apt-get install gettext-base)." >&2
  exit 1
fi

# Render values file from template with envsubst
echo ">>> Rendering ${VALUES_RENDERED} from ${VALUES_TEMPLATE}"
envsubst < "${VALUES_TEMPLATE}" > "${VALUES_RENDERED}"

# Add / update Helm repo
echo ">>> Adding/updating prometheus-community Helm repo"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# Install or upgrade kube-prometheus-stack
echo ">>> Deploying kube-prometheus-stack (release: ${RELEASE_NAME}, namespace: ${NAMESPACE})"
helm upgrade --install "${RELEASE_NAME}" prometheus-community/kube-prometheus-stack \
  -n "${NAMESPACE}" \
  -f "${VALUES_RENDERED}"

echo ">>> Done."
echo "Grafana will be available at:     https://grafana.${DOMAIN_NAME}   (once DNS/Ingress/certs are set)"
echo "Prometheus will be available at:  https://prometheus.${DOMAIN_NAME}"
echo "Grafana login: user='${GRAFANA_ADMIN_USER}', password set via GRAFANA_ADMIN_PASSWORD (or existing secret)."

