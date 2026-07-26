# Shared VPS Reverse Proxy

This stack is the only public HTTP entrypoint on the VPS. It owns ports 80/443,
TLS certificates, and routing to the sibling application stacks over the
external Docker network `shared_proxy`.

| Request | Destination |
| --- | --- |
| `https://podolog-warsaw.pl/*` | `podolog-nginx:80` |
| `https://www.podolog-warsaw.pl/*` | `301` to the same path on `podolog-warsaw.pl` |
| `https://focoris-dev.podolog-warsaw.pl/api/*` | `focoris-auth-api:3001` |
| `https://focoris-dev.podolog-warsaw.pl/*` | `focoris-web:3000` |

The nginx templates use Docker's embedded DNS resolver, so this stack can start
even while an application stack is unavailable. Requests to that unavailable
upstream return `502` until it joins the network.

## VPS prerequisites

Point DNS for the apex, `www`, and `focoris-dev` names to the VPS. Add `AAAA`
records only when the host has working public IPv6, and allow inbound TCP 80 and
443.

Create the shared network once:

```bash
docker network inspect shared_proxy >/dev/null 2>&1 || docker network create shared_proxy
```

Create the private environment file:

```bash
cp .env.example .env
```

Set a real Let's Encrypt contact address in `.env`. Domain-specific values live
there rather than in the application repositories.

## First deployment

Start the application stacks first:

```bash
cd /path/to/podolog
docker compose up --build -d

cd /path/to/focoris
cp .env.docker.example .env.docker
# Replace every placeholder in .env.docker before continuing.
docker compose --env-file .env.docker up --build -d
```

Start infra in HTTP bootstrap mode:

```bash
cd /path/to/infra
docker compose up -d
```

After DNS resolves publicly to this VPS, issue the certificates:

```bash
set -a
. ./.env
set +a

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot --webroot-path /var/www/certbot \
  --cert-name "$DOMAIN_PODOLOG" \
  --domain "$DOMAIN_PODOLOG" \
  --domain "www.$DOMAIN_PODOLOG" \
  --email "$LETSENCRYPT_EMAIL" \
  --agree-tos --no-eff-email --non-interactive

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot --webroot-path /var/www/certbot \
  --cert-name "$FOCORIS_QA_DOMAIN" \
  --domain "$FOCORIS_QA_DOMAIN" \
  --email "$LETSENCRYPT_EMAIL" \
  --agree-tos --no-eff-email --non-interactive

docker compose restart nginx
```

The `set -a` block is needed because Docker Compose reads `.env` for
interpolation but does not export its values to your shell.

After the nginx restart, HTTP redirects to HTTPS, `www` redirects to the apex,
and the focoris `/api/` prefix routes to auth-api without stripping `/api`.

## Routine operation

Certbot checks for renewal twice per day. Nginx reloads certificates every six
hours, so no application stack restart is required after renewal.

Useful checks:

```bash
docker compose ps
docker compose logs -f nginx certbot
docker network inspect shared_proxy
```

Deploy application changes from their own repositories. Recreate infra only
when its Compose or nginx files change.
