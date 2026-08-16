# GitHub setup

Cortex and Podolog workflows publish images only. They require no infra, VPS,
Kubernetes, Argo CD, or GitHub App credential.

Argo CD Image Updater uses a GitHub App installed only on
`gena-tokarev/infra`. Give it repository Contents and Pull requests read/write,
with every other permission disabled. Store its numeric App ID, installation ID
and private key in the encrypted Ansible Vault. Ansible streams them into the
`argocd-image-updater-git` Kubernetes Secret.

After Image Updater is verified, remove the obsolete `INFRA_APP_CLIENT_ID` and
`INFRA_APP_PRIVATE_KEY` values from the Cortex and Podolog environments.

Argo CD uses a separate read-only SSH deploy key. Its private half is stored in
the encrypted Ansible Vault, and its public half is registered under the infra
repository's Deploy keys.

No VPS, SSH, Kubernetes, Argo CD, Ansible Vault, SOPS, age, or infra-writer
credential belongs in application GitHub Actions. The application GHCR packages
remain public so k3s and Image Updater can read them without registry credentials.

Remove the obsolete `argocd.podolog-warsaw.pl` DNS record and GitHub OAuth App
after tunnel access is verified. The obsolete `argocd-sops-plugin` GHCR package
can also be deleted manually.
