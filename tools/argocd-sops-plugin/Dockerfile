FROM ghcr.io/getsops/sops:v3.13.0-alpine@sha256:9caf87dc33a1ecee5c6585ca3b4f993965147ad6648e770042d5d318bd1efc2d

USER root

COPY generate-manifests /usr/local/bin/generate-manifests
RUN chmod 0555 /usr/local/bin/generate-manifests

USER 999:999
WORKDIR /home/argocd/cmp-server

ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
