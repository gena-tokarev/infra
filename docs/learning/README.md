# Infrastructure learning path

This curriculum explains the infrastructure in this repository from the
inside out. It starts with the system that is running today, then extends the
same concepts toward a safer production platform.

Do not try to memorize every manifest. For each stage, first understand the
responsibility of the component, then inspect the referenced files, and only
then perform the exercise.

## Current system map

```text
Developer pushes application source
                |
                v
GitHub Actions tests and publishes images to GHCR
                |
                v
Argo CD Image Updater records new digests in this repository
                |
                v
Argo CD reconciles Git with the k3s cluster
                |
                v
Kubernetes runs Cortex, Podolog, PostgreSQL and Redis
                |
                v
Traefik + Gateway API expose HTTPS applications
```

Ansible has a separate role. It bootstraps the server, installs k3s and Argo
CD, and transfers Vault-managed secrets. It is not part of each application
deployment.

## How to use this path

Work through the stages in order. Use Lens for discovery and Argo CD for the
GitOps view, but repeat important observations with `kubectl` so the tools do
not hide the Kubernetes model.

Before experiments:

```bash
make lens-tunnel
```

In a second terminal, point `kubectl` at the development kubeconfig. Prefer
read-only commands (`get`, `describe`, `logs`, `top`) until a stage explicitly
asks for a change. Do not experiment by deleting the database, its PVC, Argo
CD, or cluster-wide resources.

## Lessons and learning objectives

The stages below are the syllabus. Detailed lesson files live beside this
index and are added as the subject is studied. A learning objective is a
specific ability you should be able to demonstrate; a Kubernetes object is a
resource such as a Pod or Service. They are unrelated uses of the word
"object."

Start with:

1. [Desired state and ownership](01-desired-state-and-ownership.md)
2. [Kubernetes objects: Pod, Deployment, Service and Namespace](02-kubernetes-objects.md)

## Stage 1: desired state and ownership

### Learn

- Desired state versus actual state.
- A controller continuously reconciles the two; Kubernetes is not a script
  that runs once.
- The boundaries between Ansible, Argo CD, Image Updater and Kubernetes.
- Why two controllers should not own the same field or resource.

### Study here

- `ansible/playbooks/bootstrap.yml`
- `ansible/roles/gitops_bootstrap/tasks/main.yml`
- `bootstrap/platform-root.yaml`
- `bootstrap/workloads-root.yaml`

### Exercise

In Argo CD, open `platform-root`, `workloads-root`, `cortex` and `podolog`.
Identify which Git file defines each Application and which namespace receives
its resources. In Lens, find one of the same resources in the live cluster.

### Checkpoint

You can explain why application deployment does not require `make bootstrap`,
and why a manual live-cluster edit may be reverted by Argo CD.

## Stage 2: core Kubernetes objects

### Learn

- A Pod is one running instance and is disposable.
- A Deployment manages interchangeable Pods and rolling updates.
- A StatefulSet gives stateful Pods stable identity and storage behavior.
- A Job runs to completion instead of staying alive.
- A Service gives changing Pods a stable internal address.
- ConfigMaps contain non-secret configuration; Secrets contain sensitive
  configuration; namespaces provide organizational and policy boundaries.

### Study here

- `charts/cortex/templates/auth-api.yaml`
- `charts/cortex/templates/web.yaml`
- `charts/cortex/templates/migration.yaml`
- `charts/podolog/templates/resources.yaml`
- `charts/cortex-data/templates/resources.yaml`

### Exercise

```bash
kubectl get namespaces
kubectl -n cortex get pods,deployments,jobs,services
kubectl -n cortex get clusters.postgresql.cnpg.io
kubectl -n podolog get pods,deployments,services
kubectl -n cortex describe deployment cortex-web
```

Trace a Cortex web Deployment through its ReplicaSet to its Pod, then find the
Service selector that targets that Pod.

### Checkpoint

Given a resource name in Lens, you can say who creates it, whether it is
replaceable, and how traffic reaches it.

## Stage 3: containers, images and scheduling

### Learn

- A container image is an immutable application filesystem and metadata; it is
  not a virtual machine and should not contain runtime secrets.
- Tags such as `main` are movable names. Digests identify exact image content.
- Requests influence scheduling; limits constrain resource consumption.
- Security contexts enforce non-root execution and reduce container powers.
- Startup, readiness and liveness probes answer different questions.

### Study here

- `environments/development/cortex/release.yaml`
- `environments/development/podolog/release.yaml`
- `charts/cortex/templates/auth-api.yaml`
- `charts/cortex/templates/web.yaml`
- `charts/podolog/templates/resources.yaml`

### Exercise

Inspect a running Pod and compare its resolved image ID with the digest in the
release file:

```bash
kubectl -n cortex get pod -l app.kubernetes.io/name=cortex-web -o wide
kubectl -n cortex describe pod -l app.kubernetes.io/name=cortex-web
kubectl -n cortex top pods
```

Then locate each probe and resource request in the Helm template.

### Checkpoint

You can explain why `main@sha256:...` is reproducible, why readiness controls
traffic, and why a process can be Running while a Pod is not Ready.

## Stage 4: networking and HTTPS

### Learn

- ClusterIP Services are private stable endpoints inside the cluster.
- DNS resolves service names such as `cortex-auth-api` inside Kubernetes.
- Gateway API describes public listeners and routing policy.
- Traefik is the implementation that reads those resources and handles actual
  traffic.
- cert-manager obtains certificates and stores them in Kubernetes Secrets.

### Study here

- `platform/config/traefik.yaml`
- `platform/config/gateway.yaml`
- `platform/config/certificates.yaml`
- `charts/cortex/templates/routing.yaml`
- `charts/podolog/templates/resources.yaml`

### Exercise

Trace both routes end to end:

```text
cortex-dev.podolog-warsaw.pl/api/* -> Gateway -> HTTPRoute -> API Service -> Pod
cortex-dev.podolog-warsaw.pl/*     -> Gateway -> HTTPRoute -> Web Service -> Pod
```

Use Lens or `kubectl describe` to inspect the Gateway, HTTPRoutes, Services and
EndpointSlices. Confirm that PostgreSQL and Redis have no public route.

### Checkpoint

You can explain the difference between Gateway API and Traefik, and diagnose
whether a failed request is DNS, TLS, routing, Service selection or Pod health.

## Stage 5: Helm, Kustomize and environment configuration

### Learn

- Helm templates reusable application resources from values.
- Kustomize assembles sets of plain manifests without templating them.
- Argo CD multi-source Applications combine a chart with environment-specific
  values.
- Rendered YAML is the contract sent to Kubernetes.

### Study here

- `charts/cortex/`
- `charts/podolog/`
- `environments/development/`
- `clusters/development/platform/kustomization.yaml`
- `clusters/development/workloads/cortex.yaml`

### Exercise

Render the Cortex chart locally and locate the image, Service and probes in the
result. Then run the repository validation:

```bash
helm template cortex charts/cortex \
  -f environments/development/cortex/values.yaml \
  -f environments/development/cortex/release.yaml
./scripts/validate.sh
```

### Checkpoint

You can predict which generated Kubernetes field will change before editing a
Helm value.

## Stage 6: GitOps and Argo CD

### Learn

- Git is the durable desired-state record; the live cluster is not.
- Argo CD compares desired manifests with live resources and reports sync and
  health separately.
- Automated sync, pruning and self-healing have different effects.
- Sync waves and hooks order operations such as migrations before workloads.
- Rollback means reverting Git, not merely changing the live cluster.

### Study here

- `clusters/development/platform/`
- `clusters/development/workloads/`
- `bootstrap/argocd/values.yaml`
- `docs/rollback.md`

### Exercise

For one Argo Application, inspect its source, rendered manifest, live manifest,
diff, sync status, health status and resource tree. Find the Git commit Argo is
currently reconciling.

### Checkpoint

You can distinguish `OutOfSync`, `Progressing`, `Degraded` and a failed sync,
and know when a hard refresh or a new Git commit is appropriate.

## Stage 7: CI, GHCR and Image Updater

### Learn

- CI validates source and produces deployable artifacts.
- GHCR stores images; it does not deploy them.
- Cortex services can be built independently.
- Image Updater resolves the movable `main` tag to a digest and writes release
  state to Git.
- Argo CD remains a reader/reconciler; Image Updater owns the Git write
  credential.

### Study here

- `platform/image-updater/image-updater.yaml`
- `clusters/development/platform/image-updater.yaml`
- `clusters/development/platform/image-updater-config.yaml`
- `environments/development/*/release.yaml`
- the Cortex and Podolog workflow files in their application repositories

### Exercise

Follow one harmless application commit across GitHub Actions, GHCR, the Image
Updater commit, Argo CD and the resulting Deployment revision. Record the SHA
or digest at every boundary.

### Checkpoint

You can identify the last successful release and prove exactly which source
commit and image digest are running.

## Stage 8: data, persistence and migrations

### Learn

- Pods are disposable; persistent volumes are not.
- A PVC requests storage, while the storage class determines how it is
  provisioned.
- CloudNativePG is an operator that manages PostgreSQL resources and lifecycle.
- Redis is currently ephemeral by design.
- Schema migrations are forward operations and must remain compatible with the
  previous application during rolling deployment and rollback.
- A PVC is not a backup.

### Study here

- `charts/cortex-data/`
- `charts/cortex/templates/migration.yaml`
- `docs/database.md`
- `docs/rollback.md`

### Exercise

Find the CloudNativePG `Cluster`, PostgreSQL Pod, PVC, StorageClass and
Services. Explain what survives a Pod restart, a Deployment rollout, a k3s
restart, disk loss and total VPS loss.

### Checkpoint

You can describe the recovery procedure and understand why production needs an
off-site, regularly restored backup.

## Stage 9: secrets and trust boundaries

### Learn

- Ansible Vault encrypts secrets at rest in Git; it does not itself provide
  secrets to running Pods.
- Ansible decrypts locally and streams Kubernetes Secret definitions to the
  API server.
- k3s secret encryption protects Kubernetes Secret data in its datastore.
- A repository deploy key, GitHub App key, application secret and TLS private
  key have different scopes and rotation procedures.
- `no_log` reduces accidental disclosure but is not a substitute for proper
  access control.

### Study here

- `docs/secrets.md`
- `ansible/vault.example.yml`
- `ansible/roles/kubernetes_secrets/tasks/main.yml`
- `ansible/roles/argocd/tasks/main.yml`

Never print or decrypt the real Vault as part of a learning exercise.

### Exercise

Create a table of every credential type, who can read it, what it authorizes,
where it is stored and how it is rotated. Verify only metadata such as Secret
names and keys in Lens—not secret values.

### Checkpoint

You can rotate one application secret without rebuilding an image or manually
restarting k3s.

## Stage 10: Ansible and reproducible bootstrap

### Learn

- Inventory selects hosts and environment variables.
- A playbook sequences roles; a role groups idempotent tasks.
- `become` performs privileged host operations.
- Handlers and changed-state reporting help avoid unnecessary work.
- Bootstrap automation and continuous reconciliation solve different problems.

### Study here

- `ansible/inventories/development/`
- `ansible/playbooks/bootstrap.yml`
- `ansible/roles/`
- `Makefile`

### Exercise

For each bootstrap role, write down its inputs, changes, idempotency boundary
and whether the result is later managed by Argo CD. Run `make ansible-check`.
Use `--check` mode only after verifying that every involved task supports it;
check mode is not a guarantee of a safe dry run.

### Checkpoint

You can explain what would be needed to recreate the platform on a replacement
VPS and which state must come from backups rather than Git.

## Stage 11: observability and systematic debugging

### Learn

- Start with symptoms, then move through DNS, edge routing, Service, endpoints,
  Pod state, events and logs.
- Events explain scheduling and lifecycle failures; logs explain application
  behavior; metrics explain resource pressure.
- Argo health answers a different question from Kubernetes readiness.
- Alerts should detect user-visible failures before manual inspection.

### Exercise

Practice diagnosing these scenarios without immediately changing anything:

1. A Pod is `CrashLoopBackOff`.
2. A Pod is Running but not Ready.
3. A Service has no endpoints.
4. Argo is OutOfSync but the application is Healthy.
5. A certificate is not Ready.
6. The VPS is under memory or disk pressure.

Write a short evidence-first checklist for each scenario.

### Checkpoint

You can find the failing layer before attempting a fix.

## Stage 12: production evolution

The current single-node development cluster is a good learning platform, but
production adds failure domains and operational obligations.

Learn and introduce these in roughly this order:

1. Automated encrypted off-site PostgreSQL backups and tested restores.
2. Monitoring, dashboards and alerts for nodes, workloads, certificates,
   backups and public endpoints.
3. Centralized logs with retention and secret redaction.
4. Separate development and production namespaces, values, secrets, domains
   and approval policies while promoting the same tested image digest.
5. Least-privilege ServiceAccounts, RBAC, NetworkPolicies and Pod Security
   Admission.
6. Resource sizing, quotas, disruption budgets and graceful shutdown.
7. Image vulnerability scanning, dependency policy and artifact provenance.
8. Upgrade procedures for k3s, Kubernetes APIs, Argo CD, operators and charts.
9. External secret management or a cloud secret manager when multiple
   operators or clusters make local Ansible Vault impractical.
10. Multiple nodes or a managed Kubernetes service only when the required
    availability justifies the added cost and complexity.

For each production change, define the failure being addressed, recovery
procedure, owner, measurable success condition and ongoing maintenance cost.
Do not add a component solely because it appears in a reference architecture.

## Completion project

Provision a disposable replacement host from the repository and documented
backups, deploy one known Cortex and Podolog release, restore PostgreSQL, and
validate HTTPS. Then explain:

- what came from Git;
- what came from Ansible Vault;
- what came from GHCR;
- what came from the database backup;
- which components continuously reconcile state;
- how to determine the exact running release;
- how the system behaves when one component fails.

Completing that exercise demonstrates operational understanding rather than
only familiarity with individual tools.
