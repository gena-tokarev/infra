# Lesson 1: desired state and ownership

## Why this comes first

Kubernetes, Argo CD, operators and Image Updater make much more sense after you
understand reconciliation. They are not a sequence of deployment commands.
They are controllers that repeatedly compare desired state with observed state
and try to remove the difference.

## Learning objectives

After this lesson, you should be able to:

1. Explain desired state, actual state, reconciliation and a controller.
2. Distinguish an object's `spec` from its `status`.
3. Identify whether Ansible, Argo CD, Image Updater or a Kubernetes controller
   owns a particular change in this system.
4. Explain why editing an Argo-managed live resource is temporary.
5. Explain why `make bootstrap` is not part of a normal application release.

## Authoritative reading

Read these official Kubernetes pages in order:

1. [Objects in Kubernetes](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
   — focus on object intent, `spec`, `status`, `apiVersion`, `kind` and
   `metadata`.
2. [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
   — focus on the thermostat analogy and the control-loop pattern.

Do not attempt to learn the entire Kubernetes documentation yet.

## The model

```text
desired state in object.spec
              |
              v
          controller --------+
              |               |
              v               |
       changes actual state   |
              |               |
              v               |
observed state in object.status
              |               |
              +---------------+
```

The loop does not necessarily finish permanently. A Pod may crash, a node may
restart, a certificate may expire, or Git may change. Controllers keep
watching.

## The control loops in this repository

| Controller or tool | Reads desired state from | Changes |
| --- | --- | --- |
| Ansible | inventory, roles and Vault | VPS bootstrap state and initial Secrets |
| Image Updater | image policy and GHCR | release files in Git |
| Argo CD | this Git repository | Kubernetes API objects |
| Deployment controller | Deployment `spec` | ReplicaSets and Pods |
| Job controller | Job `spec` | Pods that run to completion |
| CloudNativePG operator | PostgreSQL `Cluster` resource | PostgreSQL workloads and related resources |
| cert-manager | `Certificate` resources | certificate requests and TLS Secrets |

Ansible is invoked manually and is idempotent, but it is not continuously
running. The other controllers run in or around the cluster continuously.

## Repository walkthrough

Open these files without changing them:

1. `ansible/playbooks/bootstrap.yml` — the ordered bootstrap entry point.
2. `ansible/roles/gitops_bootstrap/tasks/main.yml` — creates the initial Argo
   Applications and waits for reconciliation.
3. `bootstrap/platform-root.yaml` — declares the platform root Application.
4. `bootstrap/workloads-root.yaml` — declares the workload root Application.
5. `clusters/development/workloads/cortex.yaml` — declares the Cortex Argo
   Application.

For each file ask:

- Is this desired state or a command that applies desired state?
- Who reads it?
- What resource does that reader create or update?
- Does the reader run once or continuously?

## Read-only lab

Start the Lens tunnel and open the cluster:

```bash
make lens-tunnel
```

In Lens, select the Cortex Deployment. Compare its YAML sections:

- `metadata`: identity, namespace and labels;
- `spec`: the requested configuration;
- `status`: what Kubernetes currently observes.

Repeat in a terminal:

```bash
kubectl -n cortex get deployment cortex-web -o yaml
kubectl -n cortex get deployment cortex-web \
  -o jsonpath='{.spec.replicas}{" desired, "}{.status.readyReplicas}{" ready\n"}'
```

Then inspect ownership:

```bash
kubectl -n cortex get pods \
  -l app.kubernetes.io/name=cortex-web \
  -o custom-columns='POD:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind,OWNER:.metadata.ownerReferences[0].name'
```

The immediate owner will be a ReplicaSet. The Deployment owns that
ReplicaSet, producing the chain:

```text
Deployment -> ReplicaSet -> Pod
```

## Knowledge check

Answer these without looking at the text:

1. If you delete a Deployment-managed Pod, why does another appear?
2. If Git requests one replica but you manually scale the live Deployment to
   two, what should Argo CD eventually do?
3. Why is `status` not normally committed in a manifest?
4. Which component writes Cortex image digests into Git?
5. Which component turns the resulting Deployment declaration into Pods?

## Completion criterion

This lesson is complete when you can trace:

```text
Git -> Argo Application -> Deployment -> ReplicaSet -> Pod
```

and name the controller responsible for each transition.
