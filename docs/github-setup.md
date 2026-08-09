# GitHub setup

Cortex and Podolog each need their release-promotion GitHub App values in the
environment used by their publishing workflow:

- `INFRA_APP_ID` as an environment variable
- `INFRA_APP_PRIVATE_KEY` as an environment secret

The App should be installed only on `gena-tokarev/infra` with repository contents
read/write and no other permissions. These CI credentials remain in GitHub;
Ansible Vault does not replace them.

Argo CD uses a separate read-only SSH deploy key. Its private half is stored in
the encrypted Ansible Vault, and its public half is registered under the infra
repository's Deploy keys.

No VPS, SSH, Kubernetes, Argo CD, Ansible Vault, SOPS, or age credential belongs
in GitHub Actions. The application GHCR packages remain public so k3s can pull
images without registry credentials.

Remove the obsolete `argocd.podolog-warsaw.pl` DNS record and GitHub OAuth App
after tunnel access is verified. The obsolete `argocd-sops-plugin` GHCR package
can also be deleted manually.
