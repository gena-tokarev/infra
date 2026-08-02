# Rollback

## Application release

Revert the release commit in this repository and push it:

```bash
git log -- environments/development/cortex/release.yaml
git revert <bad-release-commit>
git push
```

Argo CD deploys the preceding image digests. Database migrations are not
reversed, so every migration must remain compatible with the previous release.

## Cutover rollback

Before accepting writes in the new cluster, restore the legacy port owner:

```bash
cd /home/deploy/apps/infra
sudo ./scripts/disable-traefik.sh
docker compose start
cd /home/deploy/apps/focoris && docker compose start
cd /home/deploy/apps/podolog && docker compose start
```

Do not perform this database rollback after accepting writes in Kubernetes:
the legacy PostgreSQL volume will not contain those new writes.
