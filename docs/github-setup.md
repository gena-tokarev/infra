# GitHub setup

## DNS and OAuth

Create these DNS records:

```text
argocd.podolog-warsaw.pl A 167.233.59.107
cortex-dev.podolog-warsaw.pl A 167.233.59.107
```

Keep the old `focoris-dev.podolog-warsaw.pl` record during the rollback window.
It can be removed after the Cortex cutover is accepted.

Create a GitHub OAuth App under **Settings → Developer settings → OAuth Apps**:

```text
Homepage URL: https://argocd.podolog-warsaw.pl
Authorization callback URL: https://argocd.podolog-warsaw.pl/api/dex/callback
```

Use its client ID and client secret when creating the encrypted Argo CD Secret.

Update the Cortex Google OAuth client configuration as well:

```text
Authorized redirect URI:
https://cortex-dev.podolog-warsaw.pl/api/external-auth/google/callback

Authorized JavaScript origin:
https://cortex-dev.podolog-warsaw.pl
```

## Release promotion GitHub App

Create one GitHub App with repository **Contents: Read and write**, install it only
on `gena-tokarev/infra`, and generate one private key.

In the infra repository, set **Settings → Actions → General → Workflow
permissions** to **Read and write permissions** so the plugin image workflow can
pin its published digest back into this repository.

In Cortex's `development` environment add:

```text
Variable INFRA_APP_ID
Secret   INFRA_APP_PRIVATE_KEY
```

In Podolog's `production` environment add the same two entries plus:

```text
NEXT_PUBLIC_SITE_URL=https://podolog-warsaw.pl
NEXT_PUBLIC_BOOKSY_URL=<current public Booksy URL>
NEXT_PUBLIC_FACEBOOK_URL=<current public Facebook URL or empty>
NEXT_PUBLIC_INSTAGRAM_URL=<current public Instagram URL or empty>
```

The application environments no longer need any `DEPLOY_*` values.

After first publication, make these GHCR packages public:

- `cortex-auth-api`
- `cortex-web`
- `podolog-web`
- `argocd-sops-plugin`
