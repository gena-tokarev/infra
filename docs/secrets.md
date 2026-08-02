# SOPS and age setup

Run these commands on a trusted local machine, not on the VPS:

```bash
age-keygen -o age.key
age-keygen -y age.key
cp .sops.yaml.example .sops.yaml
```

Replace the recipient in `.sops.yaml` with the `age1...` public value. Back up
`age.key` in a password manager; it is ignored by Git and must never be committed.

Create the Cortex secret:

```bash
cp examples/cortex-runtime.secret.example.yaml cortex-runtime.secret.yaml
${EDITOR:-vi} cortex-runtime.secret.yaml
grep -q REPLACE_WITH cortex-runtime.secret.yaml && exit 1
sops --encrypt \
  --filename-override environments/development/cortex/secrets/data/cortex-runtime.sops.yaml \
  cortex-runtime.secret.yaml \
  > environments/development/cortex/secrets/data/cortex-runtime.sops.yaml
rm cortex-runtime.secret.yaml
```

Create the Argo OAuth secret:

```bash
cp examples/argocd-github-oauth.secret.example.yaml argocd-github-oauth.secret.yaml
${EDITOR:-vi} argocd-github-oauth.secret.yaml
grep -q REPLACE_WITH argocd-github-oauth.secret.yaml && exit 1
sops --encrypt \
  --filename-override environments/development/argocd/secrets/github-oauth.sops.yaml \
  argocd-github-oauth.secret.yaml \
  > environments/development/argocd/secrets/github-oauth.sops.yaml
rm argocd-github-oauth.secret.yaml
```

Verify and commit only ciphertext and the public SOPS policy:

```bash
sops --decrypt environments/development/cortex/secrets/data/cortex-runtime.sops.yaml >/dev/null
sops --decrypt environments/development/argocd/secrets/github-oauth.sops.yaml >/dev/null
git add .sops.yaml environments/development
git diff --cached
git commit -m 'chore: add encrypted cluster secrets'
git push
```
