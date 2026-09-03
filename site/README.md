# Rallyroo public site

Cloudflare Workers Static Assets serves the tracker-free Rallyroo homepage,
Privacy Policy, Terms of Service, support page, and branded `404` independently
of the home-hosted API.

## Local verification

```bash
npm ci
npm test
npm run deploy:dry-run
```

## Production delivery

The `Rallyroo Site` GitHub Actions workflow deploys changes merged to `main`
when the repository variable `CLOUDFLARE_SITE_DEPLOY_ENABLED` is `true`.
Deployment requires:

- GitHub Actions secret `CLOUDFLARE_SITE_API_TOKEN`
- GitHub Actions variable `CLOUDFLARE_ACCOUNT_ID`
- GitHub Actions variable `CLOUDFLARE_SITE_DEPLOY_ENABLED=true`

Create a dedicated Cloudflare API token with only the account and zone
permissions required to edit Workers scripts and routes. Keep its recovery copy
in a separate `rallyroo-cloudflare-site-deploy` item in the `rallyroo-prod`
1Password vault. Never add the token to this directory or a Wrangler file.

The Worker owns the custom domains `rallyroo.dev` and `www.rallyroo.dev`, with
`workers.dev` and preview URLs disabled. The Cloudflare Tunnel owns only
`api.rallyroo.dev`; do not configure the website hostnames as tunnel routes.
