# Rollback and recovery

## Pause automated image selection

Before rejecting or reverting a digest, temporarily remove the affected image
rule from `platform/image-updater/image-updater.yaml` and commit that change. Wait
until the `image-updater-config` Argo Application is `Synced`. Otherwise Image
Updater can immediately write the current bad `main` digest back into Git.

For an unmerged Podolog update, wait for the pause to synchronize and then close
the Image Updater pull request; no deployed release changed.

## Revert the release commit

Find the release history:

```bash
git log --oneline -- environments/development/cortex/release.yaml
git log --oneline -- environments/development/podolog/release.yaml
```

Revert the commit that introduced the bad digest:

```bash
git revert <release-commit>
git push origin main
```

Argo CD will reconcile the previous immutable image reference. Verify the
Deployment rollout, probes and public endpoint before restoring the Image
Updater rule.

## Re-enable updates

Do not re-enable the rule while the movable `main` tag still resolves to the bad
image. First publish or select an acceptable application image, then restore the
removed Image Updater rule through Git.

## Database limitation

Application rollback never reverses Prisma migrations. Migrations must remain
backward-compatible with the previous application version. If a release made an
incompatible database change, treat recovery as a database incident and use a
tested backup/recovery procedure rather than improvising a schema downgrade.

## Cluster or server recovery

Rerun `make bootstrap` to reconcile Ansible-managed infrastructure after a
repair. For complete VPS loss, follow [Bootstrap](bootstrap.md) on a replacement
host and restore PostgreSQL from an off-host backup. Git and container images do
not contain database data.
