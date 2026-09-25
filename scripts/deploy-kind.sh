#!/usr/bin/env bash
# Creates a local kind cluster, installs the ingress controller, builds the image and deploys.
# The CI pipeline runs this same script, so what is verified there is what you run locally.
set -euo pipefail

CLUSTER=${CLUSTER:-ledger}
IMAGE=${IMAGE:-bank-ledger-k8s:local}
INGRESS_VERSION=${INGRESS_VERSION:-controller-v1.15.1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

if ! kind get clusters | grep -qx "$CLUSTER"; then
  echo ">>> Creating the kind cluster"
  kind create cluster --config "$ROOT/k8s/kind-cluster.yaml"
fi

echo ">>> Installing the ingress controller"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/kind/deploy.yaml"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo ">>> Building the image and loading it into the cluster"
docker build -t "$IMAGE" "$ROOT"
kind load docker-image "$IMAGE" --name "$CLUSTER"

echo ">>> Deploying"
kubectl apply -k "$ROOT/k8s/overlays/local"
kubectl -n ledger rollout status statefulset/ledger-postgres --timeout=180s
kubectl -n ledger rollout status deployment/ledger-app --timeout=240s

echo ">>> Smoke test through the ingress"
curl --fail --silent --show-error --retry 10 --retry-delay 3 --retry-all-errors \
  -H 'Host: ledger.local' http://localhost/actuator/health | tee /dev/stderr | grep -q '"status":"UP"'
echo
echo "Ready. Add '127.0.0.1 ledger.local' to your hosts file and open http://ledger.local/swagger-ui.html"
