# Rollback and recovery

## Application release

Revert the relevant immutable digest commit under
`environments/development/*/release.yaml`. Argo CD reconciles the preceding
application image. Database migrations are not reversed, so migrations must
remain backward-compatible with the prior application release.

## Return to the old Docker deployment

Ansible does not automate or model this fallback. Follow the manual procedure in
[Migration](migration.md): stop k3s to release ports 80/443, then start the old
Compose projects yourself. Docker volumes are never touched by provisioning.

Do not switch back to an old database after accepting new writes in Kubernetes;
the old Docker database will not contain those writes.
