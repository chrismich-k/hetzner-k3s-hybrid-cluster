# Hetzner Hybrid k3s Cluster

Provisions and configures a hybrid Hetzner Kubernetes (k3s) cluster: **Cloud**
instances as (single or more for HA) master and additional agent/worker nodes,
and Hetzner **dedicated/Robot** servers as "infrastructure" agents, all linked
over a private Hetzner Cloud Network. Uses Debian 13 (or 12) for the node OS.

Two tools, always run in this order:

1. **[Terraform]** creates/references the servers and
   the private network, and outputs the resulting node inventory.
2. **[Ansible]** reads that Terraform output directly to
   build its inventory, configures the OS on every node, and bootstraps k3s
   plus the cluster add-ons.

## What this sets up

**`ansible/01_setup_hetzner_hybrid_cluster.yaml` (Core cluster):**

* A k3s cluster without the default `servicelb` load balancer - Traefik
  runs as a DaemonSet with `hostPort` 80/443 on whichever node(s) you mark
  as `ingress_target`, using their public IPv4.
* when multiple master nodes are found in `cluster_nodes`, sets up a
  HA cluster - uneven number of masters required. The master actively used
  for cluster joining is manually maintained via `k3s_primary_master` config.
* For hcloud servers without public IPv4, any outbound IPv4 connections
  initiated by the node use the gateway server configured via 
  `k3s_gateway_server_name` for NAT.
  Unfortunately, because of Hetzner vSwitch limitations the gateway needs
  to be an hcloud server and can't be a robot server.
  This is unrelated to Ingress.
* Hetzner Cloud Controller Manager (HCCM) and Hetzner CSI, for cloud
  (hcloud) nodes.
* cert-manager plus a Let's Encrypt `ClusterIssuer` for HTTPS ingress
  (HTTP-01 via Traefik).
* The CloudNativePG operator/CRDs.

**`ansible/02_setup_identity_platform.yaml` (Identity platform):**

* Keycloak as identity provider (operator + realm/client setup, with its
  own dedicated CloudNativePG-backed Postgres database).
* oauth2_proxy in front of Traefik, redirecting to Keycloak for login.

**`ansible/03_setup_monitoring.yaml` (Monitoring, builds on 01 and 02)**:

* Prometheus, Grafana, and Alertmanager (via the `kube_prometheus_stack`
  Helm chart), pinned to your infrastructure node(s).
* Grafana login via Keycloak SSO, with a local admin account as fallback.

**`ansible/04_setup_argocd.yaml` (ArgoCD, builds on 01 and 02):**

* ArgoCD, with login via Keycloak SSO and a local admin account as
  fallback - same pattern as Grafana above.

**`ansible/05_setup_rustfs.yaml` (RustFS, builds on 01 and 02):**

* RustFS, an S3-compatible distributed file system, with login to
  the console via Keycloak SSO.

**`ansible/06_setup_pgadmin.yaml` (pgAdmin4, builds on 01 and 02):**

* pgAdmin4, a web-based PostgreSQL administration tool, with login via
  Keycloak SSO and a local admin account as fallback.

**`ansible/25_demo_database.yaml` (Demo database, builds on 01):**

* A standalone Postgres database (CloudNativePG Cluster), pinned to
  an infrastructure node

## Prerequisites
* An account at [hetzner.com](https://www.hetzner.com/), covering both
  sides you plan to use:
  * **Cloud** (console.hetzner.com): a project, plus a Read & Write API
    token for it (*Security* → *API Tokens*). For the optional pre-existing
    hcloud servers in the project: do a "Rebuild" from the
    [Console](https://console.hetzner.com/projects) with the `Debian 13`
    or 12 image. Make sure the ssh key is installed in authorized_keys.
  * **Robot/dedicated** (robot.hetzner.com), if you're including dedicated
    servers: Webservice/App credentials (*Avatar menu* → *Settings* →
    *Webservice and App Settings*). one or more registered server and a 
    vSwitch with these servers added to it
    ([docs](https://docs.hetzner.com/networking/networks/connect-dedi-vswitch/)). 
     Servers need to be freshly installed with the
    `Debian 13` or 12 image [Robot](https://robot.hetzner.com/server) console in the
    `Linux`-Tab, and the ssh key installed in authorized_keys.
* An SSH key registered with Hetzner Cloud, and its private key locally - newly
  created hcloud servers will have this key installed.
* [Terraform](https://developer.hashicorp.com/terraform/install) (or
  OpenTofu) and [Ansible](https://docs.ansible.com/) installed locally.
* A domain (or subdomain) you control, so you can point DNS records at
  whichever node(s) you'll mark as `ingress_target` - required for
  Let's Encrypt (HTTP-01) to issue certificates for Keycloak/Grafana/etc.
* *(Optional)* An S3-compatible bucket for Terraform's remote state (e.g.
  Hetzner Object Storage). Without it Terraform just uses local state, which works
  fine but keeps state's sensitive data (API tokens, etc.) in plaintext on
  this machine's disk instead of a remote bucket.

## Quickstart

This is the minimum to go from a fresh clone to a working cluster with
ingress, TLS, Postgres, Keycloak SSO, and monitoring.

1. **Provision the infrastructure with Terraform:**
    ```bash
    cd terraform
    cp terraform.tfvars.example terraform.tfvars
    ```
    then edit it - Hetzner credentials, ssh key, and the cluster_nodes topology.

    optional: remote state backend instead of local state; skip both
    lines below to just use local state
    ```bash
    cp backend.tf.example backend.tf && $EDITOR backend.tf
    $EDITOR backend.tfvars   # create with your S3-compatible credentials
    ```
    ```bash
    terraform init   # add -backend-config=backend.tfvars if you did the optional step above
    terraform apply
    ```
2. **Point DNS at your ingress node(s).** Create A/AAAA records for
    `<cluster_domain>` and its subdomains (`keycloak.`, `auth.`, `grafana.`,
    or simply `*.<cluster_domain>`) at the public IPv4/IPv6 of whichever node(s) you gave
    `ingress_target = true` in `cluster_nodes` - see `terraform output`.

    > This will be crucial for Let's Encrypt to successfully issue certificates.
    > Each record needs to be a valid ingress node (`ingress_target = true` in
    > `cluster_nodes` resulting in a label `ingress-target=true` for the node).
    > There's some output before the Certificate Request that shows you which
    > DNS records are resolved compared to the records needed for the ingress
    > nodes, which may be helpful. Note that DNS propagation will take some
    > time depending on TTL.

3. **Set up Ansible's secrets and non-secret config:**
    ```bash
    cd ../ansible
    ansible-galaxy collection install -r requirements.yaml
    pip install -r requirements.txt
    ```

    non-secret config (domains, CIDRs, versions, ...) - copy the example
    and edit it for your cluster.
    ```bash
    cp group_vars/all/vars.yaml.example group_vars/all/vars.yaml
    $EDITOR group_vars/all/vars.yaml
    ```

    secrets - copy the example, fill in real values, then encrypt it.
    ```bash
    cp group_vars/all/vault.yaml.example group_vars/all/vault.yaml
    $EDITOR group_vars/all/vault.yaml
    ansible-vault encrypt group_vars/all/vault.yaml
    ```
4. **Ensure SSH connectivity**
    If your key has a password, set up the ssh-agent so Ansible can connect to the servers:
    ```bash
    eval $(ssh-agent -s)
    ssh-add <your-key>
    ```
    Be sure to connect to all the servers once with your key to accept the host keys:
    ```bash
    ssh -i <your-key> <user>@<server>
    ```
5. **Run the playbooks, in order:**
    ```bash
    ansible-playbook --ask-vault-pass 01_setup_hetzner_hybrid_cluster.yaml
    ansible-playbook --ask-vault-pass 02_setup_identity_platform.yaml
    ansible-playbook --ask-vault-pass 03_setup_monitoring.yaml
    ansible-playbook --ask-vault-pass 04_setup_argocd.yaml
    ```

See the .example config files for configuration details.

## Further use cases

### Change the multi-master registration node

With multiple k3s masters (`cluster_nodes` has 2+ `role = "master"` entries),
one of them is the designated "holder" of a private Hetzner Cloud Alias IP -
the address other masters/agents join *through*. To move that role to a
different, already-running master (e.g. before decommissioning the current
one):

1. In `terraform/terraform.tfvars`, change `k3s_primary_master` to
   the new master's `cluster_nodes` key.
2. `terraform apply`.
   - **If this fails with `Error: API request failed ... no_subnet_available`**,
     just run `terraform apply` again. Hetzner's API needs a moment to
     fully release the address after the old holder gives it up before it
     can be attached to the new one - Terraform has no way to express that
     wait as part of a single `apply` (the "who's currently detaching vs.
     attaching" relationship is a runtime value, not something a `depends_on`
     can capture, since either side could be the one giving it up depending
     on which master you're moving to). A short wrapper works too if you'd
     rather not do it by hand: `terraform apply || (sleep 15 && terraform apply)`.
3. `ansible-playbook 01_setup_hetzner_hybrid_cluster.yaml` again. This is
   safe to run against already-running masters - k3s ignores `cluster-init`/
   `server`/`token` entirely on a node that already has etcd data on disk,
   and `install_k3s_master` detects and cleans up the old holder's
   now-stale local alias-IP network config on its own.

### Decommission a master node

1. If the master being removed is the current `k3s_primary_master`,
   move that role to a different, already-running master first - see
   "Change the multi-master registration node" above.
2. Remove the master's entry from `cluster_nodes` in
   `terraform/terraform.tfvars`, then `terraform apply`.
3. `ansible-playbook 01_setup_hetzner_hybrid_cluster.yaml` again.
4. **Manually** remove the now-stale Node object from the cluster:
   ```bash
   kubectl delete node <removed-master-name>
   ```
   Terraform/Ansible only ever stop *managing* a removed node - neither
   ever tells the Kubernetes API "this node is gone", so its Node object
   just sits there (`NotReady`, forever) until something deletes it.
   This is a deliberately manual, un-automated step, not an oversight:
   automatically diffing `cluster_nodes` against `kubectl get nodes` and
   deleting whatever's missing would turn a transient Terraform/Ansible
   hiccup (a bad apply, a stale output, a typo) into a silent, destructive
   cluster-state change. Removing a master is rare and consequential
   enough that it should stay an explicit, deliberate action by whoever's
   actually doing it - not a side effect of routine playbook runs.

## Known issues / Troubleshooting

### A domain's TLS certificate stays stuck failing (Grafana/Keycloak/ArgoCD/auth)

Symptom: `kubectl -n <namespace> get certificate` shows `READY False` and
stays that way; `get certificaterequest,order,challenge` shows `invalid`.

1. **Check what's actually behind the domain's DNS record first** - the
   most common cause is DNS pointing at a node that isn't actually
   running Traefik (see the `ingress_target` gotcha below - either it was
   never set on that node, or it *was* set and then removed but the
   resulting label never got cleaned up). Confirm with:
   ```bash
   kubectl get pods -n kube-system -o wide | grep traefik
   kubectl -n <namespace> describe challenge <challenge-name>
   ```
   The `describe challenge` output's Events/Reason carries the actual
   ACME failure text (e.g. "connection refused" from a node with no
   Traefik pod, a DNS resolution failure, or a Let's Encrypt rate-limit
   message if you've been retrying a lot against `letsencrypt-prod`).
2. **Fixing the underlying cause does not automatically retry the
   certificate.** Once a `Certificate` has one or more
   `Failed Issuance Attempts`, cert-manager backs off before retrying -
   deleting just the failed `certificaterequest` (which cascades to
   delete its `order`/`challenge` too, via ownerReferences) does **not**
   reset that backoff clock, since the attempt counter and backoff timer
   live on the `Certificate` resource itself, not the request. To force
   an immediate, clean retry once you've actually fixed the cause, delete
   the `Certificate` itself:
   ```bash
   kubectl -n <namespace> delete certificate <name>
   ```
   then re-run whichever playbook creates it (`03_setup_monitoring.yaml`
   for Grafana, `02_setup_identity_platform.yaml` for Keycloak/auth,
   `04_setup_argocd.yaml` for ArgoCD) - the `kubernetes.core.k8s: state:
   present` task recreates it fresh, with no failure history, and
   cert-manager starts a brand new issuance attempt right away.

### Changing `ingress_target` on an existing node doesn't fully take effect

Setting `cluster_nodes[...].ingress_target = true` and re-running
`terraform apply` + `ansible-playbook 01_setup_hetzner_hybrid_cluster.yaml`
correctly *adds* the `ingress-target=true` k3s node-label and gets a
Traefik pod scheduled there - that direction works fine.

**Removing it again does not work symmetrically.** k3s/kubelet's
`--node-label` mechanism only ever *adds/ensures* the labels currently
listed in `config.yaml` when the service (re)starts - it never removes a
label that was set by a previous run but is no longer in the current
list. So after flipping `ingress_target` back to `false` and re-running
the playbook, the node keeps its stale `ingress-target=true` label
forever, Traefik's DaemonSet `nodeSelector` still matches it, and the old
Traefik pod just keeps running there untouched. Confirm with
`kubectl describe node <name>` (look for `ingress-target=true` under
`Labels:` even though `cluster_nodes` no longer sets it), then remove it
by hand:
```bash
kubectl label node <name> ingress-target-
```
