# Rollback and recovery

## Application release

Before reverting a Cortex development release, disable its Image Updater rule
with `ignoreTags: ["*"]` and wait for `image-updater-config` to synchronize.
Then revert the relevant immutable digest commit under
`environments/development/*/release.yaml`. Otherwise the controller will select
the same bad `main` digest again.

For Podolog, close an unmerged update PR. If the update was merged, disable its
rule before reverting the release commit. Re-enable updates only after `main`
points to an acceptable image. Database migrations are not reversed, so they
must remain backward-compatible with the prior application release.

## Return to the old Docker deployment

Ansible does not automate or model this fallback. Follow the manual procedure in
[Migration](migration.md): stop k3s to release ports 80/443, then start the old
Compose projects yourself. Docker volumes are never touched by provisioning.

Do not switch back to an old database after accepting new writes in Kubernetes;
the old Docker database will not contain those writes.
