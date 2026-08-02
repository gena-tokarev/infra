FROM ghcr.io/getsops/sops:v3.13.3-alpine@sha256:ae501277bf742f1662e0f881f43dd8fd6798b489a8058e921dbf6cda597140ea

USER root

COPY generate-manifests /usr/local/bin/generate-manifests
RUN chmod 0555 /usr/local/bin/generate-manifests

USER 999:999
WORKDIR /home/argocd/cmp-server

ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
