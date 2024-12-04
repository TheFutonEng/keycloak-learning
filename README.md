# Keycloak Learning

This repo follows through the exercises in the book [Keycloak - Identify and Access Management for Modern Applications (Second Edition)](https://www.amazon.com/Keycloak-Identity-Management-Applications-applications-ebook/dp/B0BPY1RDND/ref=sr_1_1?crid=3KM5T16EYE9HO&dib=eyJ2IjoiMSJ9.r7s7ZeCRIFy6Pf4SVn9xd1-iCPRLPV0JU1dZTx_UmfPGjHj071QN20LucGBJIEps.lB34ijZ8RwEEdRFCOieIdaTkY68ROR7xlAF3-QV7eOc&dib_tag=se&keywords=keycloak+-+identity+and+access+management+for+modern+applications&qid=1729806860&sprefix=keycloak+iden%2Caps%2C133&sr=8-1).  The book comes with its own Github setup published on the [Packt Github](https://github.com/PacktPublishing/Keycloak---Identity-and-Access-Management-for-Modern-Applications-2nd-Edition).  I elected to start my own repo because I want to diverge from the exercised a little bit. The upstream repo has been added here as a git submodule.  If you clone this repo, to update the submodule, run the below command:

```bash
$ git submodule update --init --recursive
```


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