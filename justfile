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
    kubectl delete namespace ingress-controller || true

# Deploy Keycloak Operator and Instance
deploy-keycloak:
    #!/usr/bin/env sh
    echo "Creating keycloak namespace..."
    kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

    echo "Deploying Keycloak Operator..."
    kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/21.1.1/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
    kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/21.1.1/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
    kubectl apply -f k8s/keycloak-operator.yaml

    echo "Waiting for operator to be ready..."
    kubectl wait --namespace keycloak \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=keycloak-operator \
        --timeout=300s

    echo "Deploying Keycloak instance..."
    kubectl apply -f k8s/keycloak-instance.yaml

    echo "Waiting for Keycloak to be ready..."
    kubectl wait --namespace keycloak \
        --for=condition=ready pod \
        --selector=app=keycloak \
        --timeout=300s

    echo "Creating Keycloak ingress..."
    kubectl apply -f k8s/keycloak-ingress.yaml

    echo "Keycloak deployment status:"
    kubectl get pods,svc,ingress -n keycloak

# Delete Keycloak deployment and cleanup resources
delete-keycloak:
    #!/usr/bin/env sh
    echo "Removing Keycloak components..."

    # Delete StatefulSet first to ensure proper PVC release
    kubectl delete statefulset -n keycloak --all --timeout=30s --ignore-not-found || true

    # Force delete any stuck pods
    echo "Force cleaning any stuck pods..."
    kubectl delete pods -n keycloak --all --force --grace-period=0 2>/dev/null || true

    echo "Removing Keycloak realm..."
    kubectl delete keycloakrealmimports.k8s.keycloak.org --all -n keycloak --timeout=30s --ignore-not-found || true

    echo "Removing Keycloak instance..."
    kubectl delete keycloak --all -n keycloak --timeout=30s --ignore-not-found || true

    echo "Removing Keycloak operator..."
    kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/21.1.1/kubernetes/keycloaks.k8s.keycloak.org-v1.yml --ignore-not-found || true
    kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/21.1.1/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml --ignore-not-found || true
    kubectl delete -f k8s/keycloak-operator.yaml --ignore-not-found || true

    # Force delete PVCs after StatefulSet is gone
    echo "Removing persistent volumes and claims..."
    kubectl delete pvc -n keycloak --all --force --grace-period=0 2>/dev/null || true

    echo "Removing ingress..."
    kubectl delete -f k8s/keycloak-ingress.yaml --ignore-not-found || true

    echo "Force removing namespace (may take a few moments)..."
    kubectl delete namespace keycloak --force --grace-period=0 || true

    echo "Cleanup complete."

# Deploy Keycloak realm and initial configuration
deploy-realm: check-keycloak
    #!/usr/bin/env sh
    echo "Deploying Keycloak realm configuration..."
    kubectl apply -f k8s/keycloak-realm.yaml

    echo "Waiting for realm to be ready..."
    kubectl wait --namespace keycloak \
        --for=condition=ready keycloakrealmimports/demo-realm \
        --timeout=300s

    echo "Realm status:"
    kubectl get keycloakrealmimports -n keycloak

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

# Get Keycloak realm status
get-realm-status:
    #!/usr/bin/env sh
    echo "Realm Import Status:"
    kubectl get keycloakrealmimports -n keycloak
    echo "\nRealm Events:"
    kubectl describe keycloakrealmimport demo-realm -n keycloak

# Delete Keycloak realm
delete-realm:
    #!/usr/bin/env sh
    echo "Deleting Keycloak realm..."
    kubectl delete -f k8s/keycloak-realm.yaml --ignore-not-found