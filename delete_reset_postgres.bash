et -euo pipefail

NS="${1:-infra}"
YAML_FILE="${2:-postgres-cnpg.yaml}"

echo "=============================================="
echo " Postgres HARD RESET script"
echo " Namespace : ${NS}"
echo " Manifest  : ${YAML_FILE}"
echo "----------------------------------------------"
echo " This will:"
echo "  - Delete all resources defined in ${YAML_FILE}"
echo "  - Delete Postgres-related Deployments/StatefulSets/Jobs in ${NS}"
echo "  - Delete PVCs in ${NS} whose names contain 'postgres' or 'pgdata'"
echo "  - Delete PVs bound to those PVCs"
echo "  - Try to delete Longhorn volumes matching PV names (if present)"
echo " ALL DATA WILL BE LOST."
echo "=============================================="
read -rp "Type 'yes' to continue: " ANSWER

if [[ "${ANSWER}" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo
echo ">>> Step 1: Deleting resources from ${YAML_FILE} (if it exists)..."
if [[ -f "${YAML_FILE}" ]]; then
  kubectl delete -f "${YAML_FILE}" -n "${NS}" --ignore-not-found --wait=false || true
else
  echo "    File ${YAML_FILE} not found, skipping manifest delete."
fi

echo
echo ">>> Step 2: Deleting obvious Postgres workloads in namespace ${NS}..."

# Delete common workload types with names starting with/containing 'postgres'
for kind in statefulset deployment job; do
  MAP=$(kubectl get "${kind}" -n "${NS}" --no-headers 2>/dev/null || true)
  if [[ -n "${MAP}" ]]; then
    # grep postgres case-insensitively
    PG_NAMES=$(echo "${MAP}" | awk 'NR>0 {print $1}' | grep -i 'postgres' || true)
    if [[ -n "${PG_NAMES}" ]]; then
      echo "    Deleting ${kind}(s):"
      echo "${PG_NAMES}" | sed 's/^/      - /'
      echo "${PG_NAMES}" | xargs -r kubectl delete "${kind}" -n "${NS}" --wait=false
    else
      echo "    No ${kind} with 'postgres' in name found."
    fi
  else
    echo "    No ${kind} resources found in ${NS}."
  fi
done

echo
echo ">>> Step 3: Finding Postgres-related PVCs in namespace ${NS}..."

PVC_NAMES=$(kubectl get pvc -n "${NS}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -Ei 'postgres|pgdata' || true)

if [[ -z "${PVC_NAMES}" ]]; then
  echo "    No PVCs with 'postgres' or 'pgdata' in name found in ${NS}."
else
  echo "    Found PVCs to delete:"
  echo "${PVC_NAMES}" | sed 's/^/      - /'

  echo
  echo ">>> Step 4: Deleting those PVCs (non-blocking)..."
  echo "${PVC_NAMES}" | xargs -r -I{} kubectl delete pvc "{}" -n "${NS}" --wait=false || true
fi

echo
echo ">>> Step 5: Deleting bound PVs for those PVCs..."

PV_NAMES=""
if [[ -n "${PVC_NAMES}" ]]; then
  for pvc in ${PVC_NAMES}; do
    # Find PV bound to this PVC
    PV=$(kubectl get pv -o jsonpath="{.items[?(@.spec.claimRef.namespace=='${NS}' && @.spec.claimRef.name=='${pvc}')].metadata.name}" 2>/dev/null || true)
    if [[ -n "${PV}" ]]; then
      for p in ${PV}; do
        echo "    PV bound to ${NS}/${pvc}: ${p}"
        PV_NAMES+="${p} "
        kubectl delete pv "${p}" --wait=false || true
      done
    else
      echo "    No PV found bound to PVC ${NS}/${pvc}"
    fi
  done
else
  echo "    No PVCs => no PVs to consider."
fi

echo
echo ">>> Step 6 (optional): Deleting Longhorn volumes matching PV names..."

if kubectl get ns longhorn-system >/dev/null 2>&1; then
  if [[ -n "${PV_NAMES}" ]]; then
    for pv in ${PV_NAMES}; do
      echo "    Trying to delete Longhorn volume '${pv}' (if it exists)..."
      kubectl -n longhorn-system delete volume "${pv}" --ignore-not-found || true
    done
  else
    echo "    No PV names collected, skipping Longhorn volume delete."
  fi
else
  echo "    Namespace 'longhorn-system' not found; skipping Longhorn cleanup."
fi

echo
echo ">>> Step 7: Summary"

echo "    Remaining PVCs in ${NS}:"
kubectl get pvc -n "${NS}" || echo "      (none or error)"

echo
echo "    Remaining PVs:"
kubectl get pv || echo "      (none or error)"

echo
echo "=============================================="
echo " Postgres reset process completed (from K8s side)."
echo " You can now re-apply ${YAML_FILE}, e.g.:"
echo "   kubectl apply -f ${YAML_FILE} -n ${NS}"
echo "=============================================="

