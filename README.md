# Keycloak/Nginx Integration

Nginx out of the box does not support OIDC.  There are a series of `just` targets that help to show off the integration that was done using [OpenResty](https://openresty.org/en/).

## Prequisites

- [just](https://github.com/casey/just) | tested version 1.36.0
- [k3d](https://k3d.io/stable/#releases) | tested version v5.7.4
- [docker](https://docs.docker.com/engine/install/) | tested version 27.3.1
- [helm](https://helm.sh/docs/intro/install/) | tested version 3.16.1

## TL;DR

```bash
just reset-all
```

The above call will do the following:

1. Deploy a local docker registry
2. Deploy a K3d cluster
3. Update coreDNS in the cluster to enable resolution for the registry spun up in step 1
4. Deploy [HAProxy](https://www.haproxy.com/) in the cluster as an ingress controller
5. Deploy [Keycloak](https://www.keycloak.org/) in the cluster
6. Setup a test realm in Keycloak and configure a user
7. Build the custom [Nginx](https://nginx.org/) image and push it to the registry stood up in step 1
8. Deploy Nginx to the cluster
9. Profit

# How to Reach Stuff

By default, the domains set for both Keycloak and Nginx are `wsp.local`.  I'm assuming that your local domain is different.  Not everything is installed using `helm` so your best bet right now is to find/replace `wsp.local` in the entire repo with your local domain.

No assumptions are made about local DNS.  Be sure to add DNS entries for `keycloak.<domain>` and `nginx.<domain>` to resolve to the IP of the host where the K3d cluster is running.

After that, you should be able to hit `http://keycloak.<domain>` and `http://nginx.<domain>`.

Credentials are below.

| User    | Password | Purpose |
| -------- | ------- | ------- |
| `admin`  | `admin123`    | Keycloak UI |
| `testuser` | `testpass123`     | SSO test user creds (against `http://nginx.<domain>/secure`)