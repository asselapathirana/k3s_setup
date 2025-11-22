# ihecluster

Bootstrap a small K3s cluster on freshly provisioned VPS nodes, then layer Longhorn storage and a Postgres/PostGIS instance on top. The scripts expect password-less SSH once bootstrapping is complete and assume the first node is the control-plane.

## Prerequisites
- VPS nodes reachable over SSH; initial user/password for the first login.
- Your public key available locally (defaults to `~/.ssh/id_rsa.pub`).
- `kubectl` installed locally.
- `nodes.txt` listing one `user@ip` per line (first line = control-plane). Example:
  ```
  assela@192.168.6.89
  assela@192.168.6.43
  ```

## Prepare config files (before running scripts)
- Copy `nodes.txt.example` to `nodes.txt` (or edit the existing file) and fill in your `user@ip` entries with the control-plane first.
- Edit `postgres-postgis.yaml`  to match your specs. 

## Files
- `init.bash`: Bootstrap a node, create user `assela`, set sudo, install your SSH key, and disable password auth.
- `setupk3s.bash`: Install K3s on the control-plane and workers from `nodes.txt`; pulls `k3s.yaml` locally with the control-plane IP injected.
- `namenodes.bash`: Label nodes as control-plane or worker based on IPs in `nodes.txt`.
- `longhorn-test-pvc.yaml`: Sanity check workload for Longhorn.
- `postgres-postgis.yaml`: Postgres + PostGIS deployment in namespace `infra`.

## Workflow
1) **Bootstrap each node**
   ```bash
   ./init.bash <password> <user@host> [pubkey_path]
   ```
   Run once per host to create `assela`, grant sudo, install your key, and disable password auth.

2) **Install K3s**
   ```bash
   ./setupk3s.bash
   export KUBECONFIG=$PWD/k3s.yaml
   ```
   The script reads `nodes.txt`, installs the control-plane on the first entry, joins the rest as workers, and writes `k3s.yaml`.

3) **Label nodes**
   ```bash
   ./namenodes.bash
   ```

4) **Install Longhorn**
   ```bash
   curl -LO https://raw.githubusercontent.com/longhorn/longhorn/v1.10.1/deploy/longhorn.yaml
   kubectl apply -f longhorn.yaml
   kubectl get pods -n longhorn-system -w
   ```
   Make Longhorn the default storage class:
   ```bash
   kubectl patch storageclass longhorn \
     -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   kubectl patch storageclass local-path \
     -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
   ```
   Sanity check:
   ```bash
   kubectl apply -f longhorn-test-pvc.yaml
   kubectl get pods
   kubectl describe pvc longhorn-test-pvc  # look for "Successfully provisioned volume"
   ```

5) **Deploy Postgres + PostGIS**
   ```bash
   kubectl create namespace infra
   # Secret must exist before applying the manifest; not stored in the YAML files.
   kubectl create secret generic postgres-secret \
     -n infra \
     --from-literal=POSTGRES_DB=lmstool \
     --from-literal=POSTGRES_USER=lmstool \
     --from-literal=POSTGRES_PASSWORD=<strong_password> \
     --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f postgres-postgis.yaml
   kubectl get pods,svc,pvc -n infra
   ```
   Optional PostGIS extension check:
   ```bash
   kubectl exec -n infra -it deploy/postgres -- \
     psql -U lmstool -d lmstool -c "CREATE EXTENSION IF NOT EXISTS postgis;"
   ```
   Service URL example: `postgresql://lmstool:<password>@postgres.infra.svc.cluster.local:5432/lmstool`
   To recall the password later (it is stored in the Kubernetes secret), run:
   ```bash
   kubectl get secret postgres-secret -n infra -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo
   ```
   To print the full URL from the secret values:
   ```bash
   NS=infra
   DB=$(kubectl get secret postgres-secret -n "$NS" -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
   USER=$(kubectl get secret postgres-secret -n "$NS" -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
   PASS=$(kubectl get secret postgres-secret -n "$NS" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
   printf 'postgresql://%s:%s@postgres.infra.svc.cluster.local:5432/%s\n' "$USER" "$PASS" "$DB"
   ```

## Notes
- Always `export KUBECONFIG=k3s.yaml` before running the cluster scripts.
- `node-token` is fetched automatically by `setupk3s.bash`; you normally do not need to edit it.
