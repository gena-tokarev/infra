# Lesson 2: Kubernetes objects

This lesson covers Pod, Deployment, Service and Namespace using Cortex rather
than an unrelated demonstration application.

## Learning objectives

After this lesson, you should be able to:

1. Read the common fields of a Kubernetes manifest: `apiVersion`, `kind`,
   `metadata` and `spec`.
2. Explain what a Pod represents and why application Pods are not managed
   directly.
3. Trace a Deployment through its ReplicaSet to its Pods.
4. Explain how a Service selects Pods and provides a stable endpoint.
5. Explain what a Namespace scopes and what it does not automatically secure.
6. Find all four object types in Lens and with `kubectl`.

## Where to learn the concepts

Use the official Kubernetes documentation as the primary source:

1. [Objects in Kubernetes](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
2. [Workloads and Pods](https://kubernetes.io/docs/concepts/workloads/)
3. [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
4. [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
5. [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
6. [Kubernetes Basics tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/)

For this lesson, read only the introductions and examples relevant to the four
objects. The Basics tutorial is optional practice; your live Cortex resources
are the main lab.

## One application, four objects

```text
Namespace: cortex
  |
  +-- Deployment: cortex-web
  |      |
  |      +-- ReplicaSet (generated)
  |             |
  |             +-- Pod: runs the web container
  |
  +-- Service: cortex-web
         |
         +-- selects healthy Pods with label
             app.kubernetes.io/name=cortex-web
```

### Pod

A Pod is Kubernetes' smallest deployable unit. It contains one or more tightly
coupled containers that share networking and volumes. Cortex currently uses
one application container per Pod.

Pods are disposable. A replacement Pod usually has a new name, UID and IP.
Do not treat a Pod like a long-lived VPS and do not manually install software
inside it.

Find the generated Pod template in:

```text
charts/cortex/templates/web.yaml
```

It is nested under:

```yaml
Deployment.spec.template
```

### Deployment

A Deployment manages interchangeable, normally stateless Pods. Its controller
creates ReplicaSets, and ReplicaSets maintain the requested number of Pods.

Cortex web declares one Deployment with a rolling-update strategy. When its
Pod template changes—most importantly when the image digest changes—the
Deployment creates a new ReplicaSet and gradually replaces the old Pods.

### Service

Pod IP addresses change. A Service provides stable DNS and a virtual IP in
front of selected Pods.

The Cortex web Service uses this selector:

```yaml
selector:
  app.kubernetes.io/name: cortex-web
```

The web Pod template carries the same label. That matching label—not the
Deployment name—connects the Service to the Pods.

The Service's `port` is the port clients use. Its `targetPort` identifies the
port on the selected Pod. In this chart `targetPort: http` refers to the named
container port `http`, which is port `3000`.

### Namespace

A Namespace scopes names and groups namespaced resources. Cortex and Podolog
can both have a Service called `web` because they are in different namespaces.

Namespaces also participate in DNS. A Service has a full internal name like:

```text
cortex-web.cortex.svc.cluster.local
```

From the same namespace, the short name `cortex-web` is sufficient.

A Namespace is not by itself a security boundary. RBAC, NetworkPolicies,
quotas and other policies are needed when actual isolation is required. Some
objects, such as Nodes, PersistentVolumes and GatewayClasses, are
cluster-scoped and do not belong to a Namespace.

## Repository walkthrough

Read these sections in order:

1. `platform/config/namespaces.yaml` — creation of the `cortex` namespace.
2. `charts/cortex/templates/web.yaml` — Service followed by Deployment.
3. `charts/cortex/values.yaml` — default replicas, image and resources.
4. `environments/development/cortex/values.yaml` — environment overrides.
5. `environments/development/cortex/release.yaml` — exact released image.

Follow these specific relationships:

```text
Deployment.spec.selector.matchLabels
    = Deployment.spec.template.metadata.labels
    = Service.spec.selector
```

If those labels do not agree, the Service will have no application endpoints.

## Read-only lab

### 1. Find the namespace

```bash
kubectl get namespaces
kubectl get namespace cortex -o yaml
```

Notice that the Namespace itself has no namespace.

### 2. Follow Deployment ownership

```bash
kubectl -n cortex get deployment cortex-web
kubectl -n cortex get replicasets \
  -l app.kubernetes.io/name=cortex-web
kubectl -n cortex get pods \
  -l app.kubernetes.io/name=cortex-web \
  -o wide
```

Use Lens to open the Deployment, its ReplicaSet and its Pod. Look at
`metadata.ownerReferences` on the ReplicaSet and Pod.

### 3. Follow Service selection

```bash
kubectl -n cortex get service cortex-web -o yaml
kubectl -n cortex get pods \
  -l app.kubernetes.io/name=cortex-web \
  --show-labels
kubectl -n cortex get endpointslice \
  -l kubernetes.io/service-name=cortex-web -o wide
```

The EndpointSlice addresses should correspond to the selected Pod addresses.

### 4. Test the Service inside the cluster

First inspect rather than creating a debug workload:

```bash
kubectl -n cortex get service cortex-web
kubectl -n cortex get endpointslice \
  -l kubernetes.io/service-name=cortex-web
```

Public HTTPS already reaches this Service through Traefik, so successful
external access plus populated endpoints is enough for this read-only lesson.

## Common misconceptions

- **A Pod is not the application definition.** The Deployment is the durable
  application workload declaration; Pods are its replaceable instances.
- **A Service does not run the application.** It selects and forwards traffic
  to Pods.
- **A Service is not necessarily public.** Cortex's Services are ClusterIP;
  Traefik provides public entry.
- **A Namespace is not a VM.** Namespaced workloads still share the cluster's
  nodes and control plane.
- **A Deployment does not directly expose a port.** The container declares a
  port, the Service provides a stable endpoint, and routing decides whether it
  becomes public.

## Knowledge check

1. If the Cortex web Pod is replaced and gets a new IP, why does the Service
   continue working?
2. Which three label locations must agree for the Deployment and Service?
3. Why is there a ReplicaSet even though the chart does not explicitly define
   one?
4. What is the difference between Service `port` and container port?
5. Can two namespaces contain Services with the same name?
6. Does placing PostgreSQL in the `cortex` namespace make it unreachable from
   every other namespace?

## Completion criterion

Without looking at the chart, draw and explain:

```text
Namespace -> Deployment -> ReplicaSet -> Pod
                                  ^
                                  |
                    Service --labels/selectors
```

Then use Lens or `kubectl` to find each live object and prove each relationship
from its metadata or selector.
