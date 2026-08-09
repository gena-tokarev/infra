# Secrets with Ansible Vault

`ansible/inventories/development/group_vars/all/vault.yml` is the only tracked
secret file. It must be encrypted as a whole with Ansible Vault. The password is
entered locally and must be backed up in a password manager; it is never put on
the VPS or in GitHub Actions.

```bash
make ansible-setup
make vault-create
make vault-edit
```

Fill every value from `ansible/vault.example.yml`. Keep the Argo administrator
password and the bcrypt hash generated from that same password in the Vault;
preflight verifies that they match. Generate it without placing the password in
shell history by running `make argocd-password-hash`. Generate a
dedicated SSH deploy key for Argo; put its private half in the Vault and add only
the public half to the private infra repository with read-only access.

Generate that dedicated key locally (it is separate from your VPS login key):

```bash
key_dir=$(mktemp -d)
ssh-keygen -t ed25519 -N '' -C argocd-infra-readonly -f "$key_dir/argocd-infra"
cat "$key_dir/argocd-infra.pub"
cat "$key_dir/argocd-infra"
```

Paste the public output into **infra → Settings → Deploy keys** without write
access, and paste the private output into
`vault_argocd_repository_private_key` using `make vault-edit`. Then securely
delete that temporary directory after confirming the encrypted Vault is backed
up. Do not reuse the GitHub App key or the VPS login key.

Ansible streams Kubernetes Secret manifests to `kubectl apply -f -`; it does not
write plaintext manifests locally or remotely. Secret-bearing tasks use
`no_log: true`, and k3s encrypts Kubernetes Secrets at rest with `secretbox`.

Rotate values with `make vault-edit`, commit the new ciphertext, then run
`make bootstrap`. Ansible reapplies both Kubernetes Secrets and restarts existing
Cortex workloads in a controlled rollout. CloudNativePG watches the labelled
`kubernetes.io/basic-auth` Secret and reconciles the database-role password.
The role (`cortex`) and database name (`cortex_auth`) are non-secret Git-managed
configuration. Changing either is a data migration and is intentionally not
automated.
