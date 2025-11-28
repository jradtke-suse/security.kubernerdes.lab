#!/bin/bash

#######################################
# Install NeuVector
#######################################
echo "Installing NeuVector..."

kubectl create namespace neuvector || true

helm repo add neuvector https://neuvector.github.io/neuvector-helm/
helm repo update

# Create NeuVector values file
cat > ./neuvector-values.yaml <<NVEOF
---
# Global runtime configuration for K3s containerd
k3s:
  enabled: true
  runtimePath: /run/k3s/containerd/containerd.sock

controller:
  replicas: 1
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists

manager:
  enabled: true
  env:
    ssl: false
  svc:
    type: ClusterIP

cve:
  scanner:
    enabled: true
    replicas: 1

enforcer:
  enabled: true
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists

# Disable other runtimes
docker:
  enabled: false

containerd:
  enabled: false

crio:
  enabled: false

# Disable CRD webhook for single-node setup
crdwebhook:
  enabled: false
NVEOF

echo "Let's install Neuvector using Helm"
helm install neuvector neuvector/core \
  --namespace neuvector \
  --set k3s.enabled=true \
  --values ./neuvector-values.yaml \
  --wait

# Wait for NeuVector to be ready
echo "Waiting for NeuVector deployment to be available..."
kubectl wait --for=condition=available --timeout=600s deployment/neuvector-controller-pod -n neuvector || true
kubectl wait --for=condition=available --timeout=600s deployment/neuvector-manager-pod -n neuvector || true

# Wait for NeuVector pods to be fully running
echo "Waiting for NeuVector pods to be ready..."
kubectl wait --for=condition=ready --timeout=600s pod -l app=neuvector-manager-pod -n neuvector || true

#######################################
# Create Ingress for NeuVector
#######################################
echo "Creating Ingress for NeuVector..."

cat > ./neuvector-ingress.yaml <<INGEOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neuvector-ingress
  namespace: neuvector
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  tls:
    - hosts:
        - security.apps.rke2-harv-dc-01.kubernerdes.lab
      secretName: tls-security-ingress
  rules:
    - host: security.apps.rke2-harv-dc-01.kubernerdes.lab
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: neuvector-service-webui
                port:
                  number: 8443
INGEOF

kubectl apply -f ./neuvector-ingress.yaml

#######################################
# Final Status
#######################################
echo "SUSE Security stack installation complete!"
echo "=========================================="
echo ""
echo "NeuVector Access:"
echo "  Default credentials: admin / admin"
echo "  IMPORTANT: Change password on first login!"
echo ""
echo ""
echo "To check deployment status:"
echo "  kubectl get pods -n neuvector"
echo "  kubectl get ingress -n neuvector"
echo ""
echo "Installation logs: /var/log/user-data.log"
ADMIN_PASSWORD=$(/usr/local/bin/kubectl get secret --namespace neuvector neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ "\n" }}')
echo "Initial admin password: $ADMIN_PASSWORD"

exit 0
