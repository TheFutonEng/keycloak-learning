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
        -f nginx/Dockerfile ./nginx
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