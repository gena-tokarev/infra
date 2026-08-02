# VPS bootstrap and cutover

All commands in this document run on the VPS unless marked **local**.

## 1. Back up legacy state

Keep the existing Compose files and volumes intact. The old checkout still has
its pre-rename path. From that legacy directory, create a custom-format
PostgreSQL dump:

```bash
mkdir -p /home/deploy/backups/cortex-cutover
chmod 700 /home/deploy/backups/cortex-cutover
cd /home/deploy/apps/focoris
docker compose exec -T postgres sh -ec \
  'pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  > /home/deploy/backups/cortex-cutover/cortex.dump
```

Export Podolog's current certificate while Certbot is still running. The old
Focoris certificate cannot be reused for the new Cortex hostname; cert-manager
will issue `cortex-dev.podolog-warsaw.pl` after Traefik takes ports 80/443.

```bash
mkdir -p /home/deploy/backups/cortex-cutover/certificates/podolog
cd /home/deploy/apps/infra
docker compose exec -T certbot cat /etc/letsencrypt/live/podolog-warsaw.pl/fullchain.pem \
  > /home/deploy/backups/cortex-cutover/certificates/podolog/fullchain.pem
docker compose exec -T certbot cat /etc/letsencrypt/live/podolog-warsaw.pl/privkey.pem \
  > /home/deploy/backups/cortex-cutover/certificates/podolog/privkey.pem
chmod -R go-rwx /home/deploy/backups/cortex-cutover
```

## 2. Install k3s without Traefik

```bash
cd /home/deploy/apps/infra
sudo ./scripts/install-k3s.sh
```

This leaves ports 80 and 443 with the current Nginx stack.

## 3. Create Argo's read-only repository key

```bash
sudo -u deploy ssh-keygen -t ed25519 \
  -f /home/deploy/.ssh/argocd_infra \
  -C argocd-infra-readonly \
  -N ''
cat /home/deploy/.ssh/argocd_infra.pub
```

Add that public key to `gena-tokarev/infra` under **Settings → Deploy keys**.
Do not enable write access. Test it:

```bash
sudo -u deploy ssh -T -i /home/deploy/.ssh/argocd_infra \
  -o IdentitiesOnly=yes git@github.com
```

Copy the backed-up local `age.key` securely to the VPS temporarily, then:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  ./scripts/bootstrap-argocd.sh \
  /absolute/path/to/age.key \
  /home/deploy/.ssh/argocd_infra
rm /absolute/path/to/age.key
```

The age identity remains in Kubernetes and in your offline backup.

## 4. Restore data and import certificates

Wait for the `cortex-data` Argo application to become healthy. Stop the legacy
Focoris API so no writes can occur after the final dump, then replace the
earlier rehearsal dump:

```bash
cd /home/deploy/apps/focoris
docker compose stop auth-api web
docker compose exec -T postgres sh -ec \
  'pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  > /home/deploy/backups/cortex-cutover/cortex-final.dump
```

Restore that final dump and import the certificates:

```bash
sudo ./scripts/restore-cortex.sh \
  /home/deploy/backups/cortex-cutover/cortex-final.dump
sudo ./scripts/import-certificates.sh \
  /home/deploy/backups/cortex-cutover/certificates
```

Before applying workloads, confirm the application workflows have replaced all
bootstrap image digests:

```bash
if grep -R 'sha256:000000' environments/development/*/release.yaml; then
  echo 'Run the Cortex and Podolog main workflows first.' >&2
  exit 1
fi
```

Apply workloads only after the restore and digest check:

```bash
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  apply -f bootstrap/workloads-root.yaml
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n argocd get applications
```

Verify internally before public cutover:

```bash
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n cortex \
  port-forward service/cortex-web 13000:3000
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n cortex \
  port-forward service/cortex-auth-api 13001:3001
```

From another SSH session, check `http://127.0.0.1:13000/auth` and
`http://127.0.0.1:13001/api/health`.

## 5. Move ports 80 and 443

Stop the legacy application and infra Compose stacks. Do not delete volumes:

```bash
cd /home/deploy/apps/podolog && docker compose stop
cd /home/deploy/apps/focoris && docker compose stop
cd /home/deploy/apps/infra && docker compose stop
sudo ss -ltnp '( sport = :80 or sport = :443 )'
```

When the final command shows no listeners:

```bash
cd /home/deploy/apps/infra
sudo ./scripts/enable-traefik.sh
```

The new Cortex certificate may take a short time to become ready while the
HTTP-01 challenge is completed:

```bash
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n gateway-system \
  wait certificate/cortex --for=condition=Ready --timeout=180s
```

Validate externally:

```bash
curl -fsSI https://podolog-warsaw.pl/pl
curl -fsS https://cortex-dev.podolog-warsaw.pl/api/health
curl -fsSI https://argocd.podolog-warsaw.pl
```

Log into Argo CD with GitHub. After that succeeds, change
`configs.cm.admin.enabled` to `false` in `bootstrap/argocd/values.yaml`, commit,
and push. Confirm password login disappears before considering cutover complete.
