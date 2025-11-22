1. create vps
2. Make it possible to login wiht ssh keys
3. create nodes.txt
4. ./init.bash <password> assela@<ip>
5. ./setupk3s.bash

Note: you need to set  export KUBECONFIG=k3s.yaml before running many scripts below

6. ./namenodes.bash
7. download longhorn.yaml from https://github.com/longhorn/longhorn/releases/tag/v1.10.1
 kubectl apply -f longhorn.yaml
8. kubectl get pods -n longhorn-system -w 
verify if everything is running or completed
9. make longhorn default
check 
 kubectl get storageclass
modify 
kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
 
 Ensure only longhorn has (default) next to it. 
10. test longhorn
kubectl apply -f longhorn-test-pvc.yaml
kubectl get pods
kubectl describe pvc longhorn-test-pvc

If the pod becomes Running and the PVC is Bound, your Longhorn-backed storage is working.
also " Successfully provisioned volume" towards the end of describe. 

11.
postgres/gis

kubectl create namespace infra
kubectl apply -f postgres-postgis.yaml

then test 
kubectl get pods -n infra
kubectl get pvc  -n infra
kubectl get svc  -n infra

Pod postgres → Running

PVC postgres-data → Bound

Service postgres → a ClusterIP

May need to run 
kubectl exec -n infra -it deploy/postgres --   psql -U lmstool -d lmstool -c "CREATE EXTENSION IF NOT EXISTS postgis;"


patch the password (currently it is change_me_strong_password !)

kubectl create secret generic postgres-secret \
  -n infra \
  --from-literal=POSTGRES_DB=lmstool \
  --from-literal=POSTGRES_USER=lmstool \
  --from-literal=POSTGRES_PASSWORD=NEW_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -
  
 The posgress url is like :postgresql://lmstool:<password>@postgres.infra.svc.cluster.local:5432/lmstool
