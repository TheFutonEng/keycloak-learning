# List available recipes
default:
    @just --list

# Create k3d cluster using configuration file
create-cluster:
    #!/usr/bin/env sh
    echo "Creating k3d cluster..."
    just delete-cluster
    echo "Creating new cluster..."
    k3d cluster create --config k3d/k3d-config.yaml --verbose

# Export kubeconfig with correct IP for remote access
export-kubeconfig:
    #!/usr/bin/env sh
    echo "Exporting kubeconfig with remote access settings..."
    # Get IP of default route interface
    HOST_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')

    # Export and modify kubeconfig
    k3d kubeconfig get keycloak | sed "s/0.0.0.0/$HOST_IP/g"

# Delete k3d cluster and clean up resources
delete-cluster:
    #!/usr/bin/env sh
    if k3d cluster list | grep -q "keycloak"; then
        echo "Deleting existing cluster..."
        k3d cluster delete keycloak
        echo "Cleaning up resources..."
        docker network rm k3d-keycloak 2>/dev/null || true
        docker volume rm k3d-keycloak-images 2>/dev/null || true
    fi

# Create and start local registry
create-registry:
    #!/usr/bin/env sh
    if ! docker ps | grep -q "k3d-registry.localhost"; then
        echo "Creating local registry..."
        k3d registry create registry.localhost --port 5111
        # Wait for registry to be ready
        sleep 2
        echo "Testing registry..."
        curl -s http://k3d-registry.localhost:5111/v2/_catalog || (
            echo "Registry is not responding properly"
            exit 1
        )
    else
        echo "Registry already exists"
    fi

# Delete local registry
delete-registry:
    #!/usr/bin/env sh
    if docker ps | grep -q "k3d-registry.localhost"; then
        echo "Deleting local registry..."
        k3d registry delete registry.localhost
    else
        echo "Registry doesn't exist"
    fi

# Build and push Nginx image
build-nginx: ensure-registry
    #!/usr/bin/env sh
    echo "Building Nginx image..."
    DOCKER_BUILDKIT=1 docker build \
        -t k3d-registry.localhost:5111/custom-nginx:latest \
        -f nginx/Dockerfile nginx
    echo "Pushing image to local registry..."
    docker push k3d-registry.localhost:5111/custom-nginx:latest

# Ensure registry exists
ensure-registry:
    #!/usr/bin/env sh
    if ! docker ps | grep -q "k3d-registry.localhost"; then
        echo "Local registry not found. Creating..."
        just create-registry
    fi

# Get cluster information
cluster-info:
    #!/usr/bin/env sh
    echo "Cluster Status:"
    k3d cluster list
    echo "\nKubernetes Nodes:"
    kubectl get nodes -o wide
    echo "\nKubernetes Contexts:"
    kubectl config get-contexts
    echo "\nLocal Registry:"
    docker ps | grep k3d-registry.localhost || echo "No local registry running"
    echo "\nAvailable Images:"
    curl -s http://k3d-registry.localhost:5111/v2/_catalog || echo "Registry not accessible"

# Check cluster health
check-cluster:
    #!/usr/bin/env sh
    echo "Node Status:"
    kubectl get nodes
    echo "\nPod Status:"
    kubectl get pods -A
    echo "\nService Status:"
    kubectl get services -A

# Forward local ports to cluster (useful for debugging)
port-forward PORT SERVICE_NAME NAMESPACE="default":
    #!/usr/bin/env sh
    echo "Forwarding port {{PORT}} to {{SERVICE_NAME}} in namespace {{NAMESPACE}}"
    kubectl port-forward -n {{NAMESPACE}} service/{{SERVICE_NAME}} {{PORT}}:{{PORT}}

# Deploy HAProxy ingress controller
deploy-ingress:
    #!/usr/bin/env sh
    echo "Creating ingress-controller namespace..."
    kubectl create namespace ingress-controller --dry-run=client -o yaml | kubectl apply -f -

    echo "Adding HAProxy helm repository..."
    helm repo add haproxytech https://haproxytech.github.io/helm-charts
    helm repo update

    echo "Cleaning up any existing HAProxy resources..."
    kubectl delete configmap -n ingress-controller haproxy-ingress --ignore-not-found

    echo "Deploying HAProxy ingress controller..."
    helm upgrade --install haproxy-ingress haproxytech/kubernetes-ingress \
        --namespace ingress-controller \
        -f k8s/haproxy-values.yaml \
        --wait

    echo "Waiting for HAProxy ingress controller to be ready..."
    kubectl wait --namespace ingress-controller \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=kubernetes-ingress \
        --timeout=300s

    echo "HAProxy ingress controller deployment status:"
    kubectl get pods,svc -n ingress-controller

# Clean up HAProxy
delete-ingress:
    #!/usr/bin/env sh
    echo "Removing HAProxy ingress controller..."
    helm uninstall haproxy-ingress -n ingress-controller || true
    # kubectl delete namespace ingress-controller || true

# Deploy Keycloak using Helm
deploy-keycloak:
    #!/usr/bin/env sh
    echo "Creating keycloak namespace..."
    kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

    echo "Adding Bitnami helm repository..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update

    echo "Deploying Keycloak with Helm..."
    helm upgrade --install keycloak bitnami/keycloak \
        --namespace keycloak \
        --values k8s/keycloak-values.yaml \
        --wait \
        --timeout 10m

    echo "Keycloak deployment status:"
    kubectl get pods,svc,ingress -n keycloak

# Delete Keycloak deployment
delete-keycloak:
    #!/usr/bin/env sh
    echo "Removing Keycloak..."
    helm uninstall keycloak -n keycloak || true

    echo "Removing PVCs..."
    kubectl delete pvc -n keycloak --all --timeout=30s || true

    echo "Removing namespace..."
    kubectl delete namespace keycloak --timeout=30s || true

    echo "Cleanup complete."

# Apply the initial realm configuration
setup-realm:
    #!/usr/bin/env sh
    echo "Creating Keycloak realm configuration..."
    kubectl apply -f k8s/keycloak-realm.yaml

    echo "Waiting for Keycloak to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=keycloak -n keycloak --timeout=300s

    echo "Importing realm configuration..."
    POD_NAME=$(kubectl get pod -l app.kubernetes.io/instance=keycloak -n keycloak -o jsonpath='{.items[0].metadata.name}')
    kubectl cp k8s/keycloak-realm.yaml keycloak/$POD_NAME:/tmp/realm.yaml

    # Import the realm using kcadm.sh
    kubectl exec -n keycloak $POD_NAME -- bash -c '\
        export KEYCLOAK_ADMIN=admin && \
        export KEYCLOAK_ADMIN_PASSWORD=admin123 && \
        /opt/bitnami/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user $KEYCLOAK_ADMIN --password $KEYCLOAK_ADMIN_PASSWORD && \
        /opt/bitnami/keycloak/bin/kcadm.sh create realms -f /tmp/realm.yaml'


# Get Keycloak status and realm info
get-realm-info:
    #!/usr/bin/env sh
    POD_NAME=$(kubectl get pod -l app.kubernetes.io/instance=keycloak -n keycloak -o jsonpath='{.items[0].metadata.name}')
    echo "Realm List:"
    kubectl exec -n keycloak $POD_NAME -- bash -c '\
        export KEYCLOAK_ADMIN=admin && \
        export KEYCLOAK_ADMIN_PASSWORD=admin123 && \
        /opt/bitnami/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user $KEYCLOAK_ADMIN --password $KEYCLOAK_ADMIN_PASSWORD && \
        /opt/bitnami/keycloak/bin/kcadm.sh get realms'

# Reset admin password
reset-admin-password PASSWORD:
    #!/usr/bin/env sh
    POD_NAME=$(kubectl get pod -l app.kubernetes.io/instance=keycloak -n keycloak -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n keycloak $POD_NAME -- bash -c '\
        export KEYCLOAK_ADMIN=admin && \
        export KEYCLOAK_ADMIN_PASSWORD={{PASSWORD}} && \
        /opt/bitnami/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user $KEYCLOAK_ADMIN --password $KEYCLOAK_ADMIN_PASSWORD && \
        /opt/bitnami/keycloak/bin/kcadm.sh update users/ADMIN_USER_ID -r master -s "credentials[0].value={{PASSWORD}}"'

# Get Keycloak URL and status
get-keycloak-url:
    #!/usr/bin/env sh
    echo "Keycloak URLs:"
    echo "Main URL: http://keycloak.wsp.local:8080"
    echo "Admin Console: http://keycloak.wsp.local:8080/admin"
    echo "\nIngress Status:"
    kubectl get ingress -n keycloak
    echo "\nEndpoint Status:"
    kubectl get endpoints -n keycloak

# Verify DNS resolution
check-dns:
    #!/usr/bin/env sh
    echo "Testing DNS resolution for keycloak.wsp.local..."
    getent hosts keycloak.wsp.local || echo "DNS entry not found"
    echo "\nTesting connection to Keycloak..."
    curl -I http://keycloak.wsp.local:8080 || echo "Connection failed"

# Ensure Keycloak is running before deploying realm
check-keycloak:
    #!/usr/bin/env sh
    if ! kubectl get keycloak -n keycloak keycloak >/dev/null 2>&1; then
        echo "Keycloak instance not found. Please run 'just deploy-keycloak' first."
        exit 1
    fi
    if ! kubectl wait --namespace keycloak --for=condition=ready pod --selector=app=keycloak --timeout=10s >/dev/null 2>&1; then
        echo "Keycloak pods are not ready. Please ensure Keycloak is running."
        exit 1
    fi

# Delete Keycloak realm
delete-realm:
    #!/usr/bin/env sh
    echo "Deleting Keycloak realm..."
    kubectl delete -f k8s/keycloak-realm.yaml --ignore-not-found

# Get detailed Keycloak status
debug-keycloak:
    #!/usr/bin/env sh
    echo "\nAll pods with labels:"
    kubectl get pods --show-labels -n keycloak

    echo "\nKeycloak events:"
    kubectl get events -n keycloak --sort-by='.lastTimestamp'

    echo "\nKeycloak container logs:"
    kubectl logs -n keycloak keycloak-0 || true

# Test HTTP connectivity
test-http:
    #!/usr/bin/env sh
    echo "Testing Keycloak HTTP endpoints..."

    echo "\nTesting main endpoint:"
    curl -v http://keycloak.wsp.local:8080/

    echo "\nTesting admin console:"
    curl -v http://keycloak.wsp.local:8080/admin

    echo "\nTesting health endpoint:"
    curl -v http://keycloak.wsp.local:8080/health/ready

# Debug HTTP setup
debug-http:
    #!/usr/bin/env sh
    echo "Checking Keycloak pod status..."
    kubectl get pods -n keycloak

    echo "\nKeycloak environment variables:"
    kubectl exec -n keycloak deployment/keycloak -- env | grep -i 'kc_\|keycloak'

    echo "\nHAProxy ingress configuration:"
    kubectl get ingress -n keycloak -o yaml

    echo "\nKeycloak logs:"
    kubectl logs -n keycloak -l app.kubernetes.io/name=keycloak --tail=50

# Get Keycloak access information
get-access-info:
    #!/usr/bin/env sh
    echo "Keycloak Access Information:"
    echo "Main URL: http://keycloak.wsp.local:8080"
    echo "Admin Console: http://keycloak.wsp.local:8080/admin"
    echo "Default admin credentials:"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo "\nIngress Status:"
    kubectl get ingress -n keycloak

# Setup cert-manager and configure with intermediate CA
setup-cert-manager: create-ca-secret deploy-cert-manager create-cluster-issuer

# Install cert-manager using Helm
deploy-cert-manager:
    #!/usr/bin/env sh
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm upgrade --install \
        cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set installCRDs=true \
        --wait
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=60s

# Create the CA secret for cert-manager
create-ca-secret:
    #!/usr/bin/env sh
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret tls intermediate-ca-key-pair \
        --cert=ca/intermediate.cert.pem \
        --key=ca/intermediate.key.pem \
        --namespace=cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -

# Create the ClusterIssuer
create-cluster-issuer:
    kubectl apply -f k8s/cluster-issuer.yaml

# Verify cert-manager setup
verify-cert-manager:
    #!/usr/bin/env sh
    kubectl get pods -n cert-manager
    kubectl get secret intermediate-ca-key-pair -n cert-manager
    kubectl get clusterissuer wsp-intermediate-ca -o wide
    kubectl logs -l app.kubernetes.io/instance=cert-manager -n cert-manager --tail=20

# Create test certificate
create-test-cert:
    kubectl apply -f k8s/test-cert.yaml
    kubectl wait --for=condition=Ready certificate test-cert --timeout=60s

# Clean up test certificate
clean-test-cert:
    kubectl delete -f k8s/test-cert.yaml --ignore-not-found

# Create namespace and certs for HAProxy
create-certs:
    #!/usr/bin/env sh
    echo "Creating ingress-controller namespace..."
    kubectl create namespace ingress-controller --dry-run=client -o yaml | kubectl apply -f -

    echo "Creating certificate for HAProxy..."
    kubectl apply -f k8s/haproxy-cert.yaml

    echo "Waiting for certificate to be ready..."
    kubectl wait --for=condition=Ready certificate -n ingress-controller haproxy-cert --timeout=60s

    echo "\nCertificate status:"
    kubectl get certificate -n ingress-controller haproxy-cert

# Verify and fix HAProxy TLS secret format
fix-haproxy-tls:
    #!/usr/bin/env sh
    echo "Extracting current TLS secret..."
    kubectl get secret -n ingress-controller haproxy-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/tls.crt
    kubectl get secret -n ingress-controller haproxy-tls -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/tls.key

    echo "Creating combined PEM file..."
    cat /tmp/tls.crt /tmp/tls.key > /tmp/tls.pem

    echo "Creating new secret..."
    kubectl create secret generic haproxy-tls \
        --namespace ingress-controller \
        --from-file=tls.crt=/tmp/tls.crt \
        --from-file=tls.key=/tmp/tls.key \
        --from-file=tls.pem=/tmp/tls.pem \
        -o yaml --dry-run=client | kubectl apply -f -

    echo "Cleaning up..."
    rm -f /tmp/tls.crt /tmp/tls.key /tmp/tls.pem

    echo "Restarting HAProxy pods..."
    kubectl rollout restart deployment -n ingress-controller haproxy-ingress-kubernetes-ingress 2>/dev/null || true
    kubectl rollout restart daemonset -n ingress-controller haproxy-ingress-kubernetes-ingress 2>/dev/null || true

# Reset everything and create a fresh cluster with all components
reset-all:
    #!/usr/bin/env sh
    echo "Deleting existing cluster..."
    just delete-cluster

    echo "Creating fresh cluster..."
    just create-cluster

    echo "Setting up cert-manager..."
    just setup-cert-manager

    echo "Creating TLS certificates..."
    just create-certs

    echo "Deploying HAProxy ingress with TLS..."
    just deploy-ingress

    echo "Deploying Keycloak..."
    just deploy-keycloak

    echo "Waiting for all pods to be ready..."
    kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=300s
    kubectl wait --for=condition=ready pod --all -n ingress-controller --timeout=300s
    kubectl wait --for=condition=ready pod --all -n keycloak --timeout=300s