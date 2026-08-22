# GitHub webhooks

GitHub webhooks remove the normal polling delay from the release flow while
keeping the Argo CD dashboard private. Only these exact HTTPS endpoints are
public:

```text
https://webhooks.podolog-warsaw.pl/api/webhook
https://webhooks.podolog-warsaw.pl/webhook?type=ghcr.io
```

The first notifies Argo CD about changes to `infra`. The second notifies Image
Updater about published GHCR images. Traefik does not route `/`, the Argo UI or
other Argo API paths on this hostname.

Polling remains enabled as a fallback. A missed webhook therefore delays an
update; it does not permanently lose it.

## 1. Verify DNS

`webhooks.podolog-warsaw.pl` must resolve to the VPS:

```bash
dig +short webhooks.podolog-warsaw.pl A
```

Expected:

```text
167.233.59.107
```

The existing `*.podolog-warsaw.pl` A record already covers this hostname. No
additional DNS record is needed while that wildcard remains in place.

## 2. Generate two independent secrets

Generate the values locally and save them temporarily in the password manager:

```bash
openssl rand -hex 32
openssl rand -hex 32
```

Use the first output for the Argo CD Git webhook and the second for GHCR image
notifications. They are independent credentials and should not be reused for
the GitHub App, Argo login or application secrets.

Open the encrypted Vault:

```bash
cd /Users/genatokarev/Projects/infra
make vault-edit
```

Add:

```yaml
vault_argocd_github_webhook_secret: FIRST_GENERATED_VALUE
vault_image_updater_ghcr_webhook_secret: SECOND_GENERATED_VALUE
```

Save and close the editor. Only encrypted Vault ciphertext may be committed.

## 3. Validate, commit and apply

```bash
make ansible-check
git status --short
git add ansible clusters docs platform README.md
git commit -m "feat(gitops): add secured deployment webhooks"
git push origin main
make bootstrap
```

Bootstrap stores the two secrets in Kubernetes without logging them, installs
the Argo webhook secret, enables the Image Updater webhook service and waits for
the `webhooks.podolog-warsaw.pl` certificate.

Verify the public plumbing before configuring GitHub:

```bash
kubectl -n gateway-system get certificate webhooks
kubectl -n gateway-system get httproute \
  argocd-github-webhook image-updater-ghcr-webhook
kubectl -n argocd get service argocd-image-updater
curl -I https://webhooks.podolog-warsaw.pl/
```

The certificate must be `Ready=True`, both routes must be accepted, and the
Image Updater Service must be `ClusterIP`. The final request should return
`404`; that confirms the hostname does not expose a general UI route.

## 4. Add the infra Git webhook

Open **gena-tokarev/infra → Settings → Webhooks → Add webhook** and enter:

```text
Payload URL:      https://webhooks.podolog-warsaw.pl/api/webhook
Content type:     application/json
Secret:           the vault_argocd_github_webhook_secret value
SSL verification: Enable SSL verification
Events:           Just the push event
Active:           enabled
```

This is a repository webhook. It is separate from the release-promotion GitHub
App, whose own webhook remains disabled.

After saving, open **Recent Deliveries**. GitHub sends a ping immediately; it
must receive a successful 2xx response.

## 5. Add the Cortex GHCR webhook

Open **gena-tokarev/cortex → Settings → Webhooks → Add webhook** and enter:

```text
Payload URL:      https://webhooks.podolog-warsaw.pl/webhook?type=ghcr.io
Content type:     application/json
Secret:           the vault_image_updater_ghcr_webhook_secret value
SSL verification: Enable SSL verification
Events:           Let me select individual events → Packages
Active:           enabled
```

Disable Pushes if GitHub selected it automatically; only **Packages** is
required for Image Updater. The Cortex GHCR packages must remain connected to
the Cortex repository so their `published` package events are delivered there.

## 6. Add the Podolog GHCR webhook

Repeat step 5 under **gena-tokarev/podolog → Settings → Webhooks**, using the
same URL and the same Image Updater GHCR secret. Select only **Packages**.

The one GHCR secret is intentionally shared by these two registry webhooks
because Image Updater supports one GHCR verification secret per controller.

## 7. Test the complete flow

Keep the relevant logs open:

```bash
kubectl -n argocd logs \
  deployment/argocd-image-updater-controller \
  --since=10m --follow
```

Push an application change that publishes an image. After GitHub finishes the
image build, its Packages webhook should trigger Image Updater within seconds.
Cortex should produce an infra commit; Podolog should produce an infra pull
request.

After merging an infra pull request, inspect the infra webhook under **Recent
Deliveries** and then check:

```bash
kubectl -n argocd get applications cortex podolog
```

Argo CD should refresh within seconds and Kubernetes should start the relevant
rollout. The remaining time is image pulling and readiness checking, not change
detection.

## Security controls

- GitHub signs both webhook types; the controllers verify their independent
  Vault-managed secrets.
- Traefik accepts only the exact `/api/webhook` and `/webhook` paths.
- Traefik rejects request bodies larger than 1 MiB.
- Traefik allows an average of 60 requests per minute with a burst of 10.
- Image Updater also limits its webhook processing to 120 requests per hour.
- TLS is terminated by Traefik using a cert-manager certificate.
- Argo CD and Image Updater remain `ClusterIP` services.
- The Argo dashboard remains accessible only through `make argocd-tunnel`.

## Disable or rotate webhooks

To disable event-driven updates, deactivate or delete the three repository
webhooks in GitHub. Polling continues automatically; no cluster change is
required.

To rotate either secret:

1. generate a new value with `openssl rand -hex 32`;
2. update it with `make vault-edit`;
3. commit the encrypted Vault and run `make bootstrap`;
4. immediately replace the corresponding GitHub webhook secret;
5. use **Recent Deliveries → Redeliver** to verify it.

Deliveries made between steps 3 and 4 can fail authentication, but polling
provides the fallback.
