# List available recipes
default:
    @just --list

# Create k3d cluster using configuration file
create-cluster:
    #!/usr/bin/env sh
    echo "Creating k3d cluster..."
    k3d cluster create --config k3d/config.yaml

# Delete k3d cluster
delete-cluster:
    #!/usr/bin/env sh
    echo "Deleting k3d cluster..."
    k3d cluster delete keycloak

# Get cluster information
cluster-info:
    #!/usr/bin/env sh
    echo "Cluster information:"
    k3d cluster list
    echo "\nKubernetes context information:"
    kubectl config get-contexts

# Check if cluster is ready
check-cluster:
    #!/usr/bin/env sh
    echo "Checking cluster nodes..."
    kubectl get nodes
    echo "\nChecking cluster pods..."
    kubectl get pods --all-namespaces