# List available recipes
default:
    @just --list


# Define template at the top level
inspect_template := "{{range $net, $conf := .NetworkSettings.Networks}}{{if eq $net \"k3d-keycloak\"}}{{$conf.IPAddress}}{{end}}{{end}}"


# Create k3d cluster using configuration file
deploy-cluster: delete-cluster
    #!/usr/bin/env sh
    echo "Creating k3d cluster..."
    k3d cluster create --config k3d/k3d-option1.yaml

    # Wait for cluster to be ready
    echo "Waiting for cluster to be ready..."
    kubectl wait --for=condition=ready node --all --timeout=60s

    # # Create registry configuration in the cluster
    # echo "Configuring registry access..."
    # kubectl create configmap registry-config \
    #     --from-literal=registries.yaml="mirrors: {\"k3d-registry.localhost:5111\": {\"endpoints\": [\"http://k3d-registry.localhost:5111\"]}}" \
    #     -n kube-system \
    #     --dry-run=client -o yaml | kubectl apply -f -

    # # Restart containerd to pick up registry changes (if needed)
    # echo "Restarting k3d node to apply registry configuration..."
    # docker restart k3d-keycloak-server-0


# Delete k3d cluster and clean up resources
delete-cluster:
    #!/usr/bin/env sh
    if k3d cluster list | grep -q "keycloak"; then
        echo "Deleting existing cluster..."
        k3d cluster delete keycloak
        echo "Cleaning up resources..."
        docker network rm k3d-keycloak 2>/dev/null || true
        docker volume rm k3d-keycloak-images 2>/dev/null || true
    else
      echo "Cluster does not exist"
    fi


# Create and start local registry
deploy-registry: delete-registry
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
        -f nginx/Dockerfile nginx \
        --no-cache
    echo "Pushing image to local registry..."
    docker push k3d-registry.localhost:5111/custom-nginx:latest


# Ensure registry exists
ensure-registry:
    #!/usr/bin/env sh
    if ! docker ps | grep -q "k3d-registry.localhost"; then
        echo "Local registry not found. Creating..."
        just create-registry
    fi

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
        -f k8s/haproxy-option1-values.yaml \
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


# Deploy minimal Keycloak for testing
deploy-keycloak:
    #!/usr/bin/env sh
    echo "Creating keycloak namespace..."
    kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

    echo "Adding Bitnami helm repository..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update

    echo "Deploying minimal Keycloak..."
    helm upgrade --install keycloak bitnami/keycloak \
        --namespace keycloak \
        --values k8s/keycloak-option1-values.yaml \
        --wait \
        --timeout 5m

    echo "Waiting for Keycloak to be ready..."
    kubectl wait --namespace keycloak \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=keycloak \
        --timeout=300s

    echo "Keycloak service details:"
    kubectl get svc -n keycloak


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


# Setup test realm in Keycloak using REST API
setup-test-realm:
    #!/usr/bin/env sh
    echo "Creating test realm configuration..."
    kubectl apply -f k8s/keycloak-test-realm.yaml

    echo "Waiting for Keycloak pod..."
    kubectl wait --namespace keycloak \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=keycloak \
        --timeout=300s

    echo "Getting access token..."
    TOKEN=$(kubectl exec -n keycloak keycloak-0 -- curl -s -X POST http://keycloak.wsp.local/realms/master/protocol/openid-connect/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=admin123" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token')

    echo "Importing realm configuration..."
    kubectl get configmap test-realm -n keycloak -o jsonpath='{.data.realm\.json}' | kubectl exec -i -n keycloak keycloak-0 -- sh -c 'cat > /tmp/realm.json'

    echo "Creating realm via API..."
    kubectl exec -n keycloak keycloak-0 -- curl -s -X POST http://keycloak.wsp.local/admin/realms \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d @/tmp/realm.json


# Delete test realm
delete-test-realm:
    #!/usr/bin/env sh
    echo "Getting access token..."
    TOKEN=$(kubectl exec -n keycloak keycloak-0 -- curl -s -X POST http://keycloak.wsp.local/realms/master/protocol/openid-connect/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=admin123" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token')

    echo "Deleting test realm..."
    kubectl exec -n keycloak keycloak-0 -- curl -s -X DELETE http://keycloak.wsp.local/admin/realms/test \
        -H "Authorization: Bearer $TOKEN"


# Deploy test Nginx instance
deploy-nginx:
    #!/usr/bin/env sh
    echo "Creating nginx namespace..."
    kubectl create namespace nginx --dry-run=client -o yaml | kubectl apply -f -

    echo "Deploying test Nginx..."
    kubectl apply -f k8s/nginx-option1.yaml

    echo "Waiting for Nginx to be ready..."
    kubectl wait --namespace nginx \
        --for=condition=ready pod \
        --selector=app=nginx-test \
        --timeout=300s

    echo "Nginx service details:"
    kubectl get svc -n nginx


# Clean up Nginx test environment
delete-nginx:
    #!/usr/bin/env sh
    echo "Removing nginx namespaces..."
    kubectl delete namespace nginx --ignore-not-found


nginx-reload: delete-nginx build-nginx deploy-nginx

# Configure CoreDNS and containerd for registry access
configure-registry-dns:
    #!/usr/bin/env sh
    echo "Getting registry IP..."
    REGISTRY_IP=`docker inspect k3d-registry.localhost --format '{{inspect_template}}'`
    echo "Registry IP: $REGISTRY_IP"

    echo "Updating CoreDNS configuration..."
    kubectl get configmap -n kube-system coredns -o yaml | \
        sed "s/NodeHosts: |.*/NodeHosts: |\n    172.19.0.3 k3d-keycloak-server-0\n    $REGISTRY_IP k3d-registry.localhost/" | \
        kubectl apply -f -

    echo "Creating containerd registry configuration..."
    echo "mirrors:" > /tmp/registries.yaml
    echo "  \"k3d-registry.localhost:5000\":" >> /tmp/registries.yaml
    echo "    endpoint:" >> /tmp/registries.yaml
    echo "      - \"http://k3d-registry.localhost:5000\"" >> /tmp/registries.yaml
    echo "    insecure: true" >> /tmp/registries.yaml
    echo "configs: {}" >> /tmp/registries.yaml

    echo "Applying containerd configuration..."
    docker cp /tmp/registries.yaml k3d-keycloak-server-0:/etc/rancher/k3s/registries.yaml
    rm /tmp/registries.yaml

    echo "Restarting k3d node..."
    docker restart k3d-keycloak-server-0

    echo "Waiting for node to be ready..."
    sleep 5
    kubectl wait --for=condition=ready node --all --timeout=60s

    echo "Restarting CoreDNS..."
    kubectl rollout restart -n kube-system deployment/coredns
    kubectl rollout status -n kube-system deployment/coredns


# Reset everything and create a fresh cluster with all components
reset-all:
    #!/usr/bin/env sh
    echo "Creating in-cluster registry..."
    just deploy-registry

    echo "Deploying fresh cluster..."
    just deploy-cluster

    echo "Fixing coreDNS for in-cluster registry..."
    just configure-registry-dns

    echo "Deploying HAProxy ingress..."
    just deploy-ingress

    echo "Deploying Keycloak..."
    just deploy-keycloak

    echo "Configuring Keycloak test realm..."
    just setup-test-realm

    echo "Building Nginx image..."
    just build-nginx

    echo "Deploying Nginx..."
    just deploy-nginx

    echo "Waiting for all pods to be ready..."
    kubectl wait --for=condition=ready pod --all -n ingress-controller --timeout=300s
    kubectl wait --for=condition=ready pod --all -n keycloak --timeout=300s
    kubectl wait --for=condition=ready pod --all -n nginx --timeout=300s