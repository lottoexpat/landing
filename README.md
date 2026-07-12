# LottoExpat — landing site

The marketing site for **lottoexpat.de** (and `www.lottoexpat.de`). A single, self-contained
static page: [`index.html`](index.html) holds all the markup, CSS, and JS inline — no framework,
no build step, no bundler. You edit `index.html` directly (Claude Code is great for this) and run
one command to publish.

---

## How it's served (the important part)

`lottoexpat.de` is **not** hosted on a server you manage. It's served entirely by **Cloudflare**,
reading the files **directly from a Cloudflare R2 bucket** called `lottoexpat-web`:

```
Browser ──HTTPS──► Cloudflare edge
                     │  (lottoexpat.de is a "Custom Domain" attached to a Worker)
                     ▼
              Worker: eigenheim-marketing
                     │  reads the file from R2 by request path
                     ▼
              R2 bucket: lottoexpat-web   ──►  index.html (+ any assets)
```

- **R2** is Cloudflare's object storage (like AWS S3). Your site files live there.
- A small **Cloudflare Worker** named `eigenheim-marketing` sits in front of the bucket. When a
  request comes in for `lottoexpat.de/…`, the Worker looks up the matching file in `lottoexpat-web`
  and returns it. The exact same Worker also serves `cineosio.dev` from a different bucket — it
  picks the bucket by the request's hostname.
- `lottoexpat.de` + `www.lottoexpat.de` are wired to that Worker as **Workers Custom Domains**, so
  Cloudflare manages the DNS record and the HTTPS certificate automatically.

### Why a Worker instead of "R2 public bucket" or Cloudflare Pages?

- A raw **R2 custom domain** serves objects only by their exact key. It has **no concept of a
  "directory index"** — a request for `/` would 404 instead of returning `index.html`. The Worker
  adds that: `/` → `index.html`, `/foo/` → `foo/index.html`, and an unknown path falls back to
  `index.html` (so deep links never hard-404).
- We already run this Worker for the CINEOS marketing site, so LottoExpat rides the same, proven
  setup — one place to reason about, one place to roll back.
- HTML is returned **no-cache** by the Worker (`Cache-Control: max-age=0, must-revalidate`), so an
  edit is visible the moment you deploy. (Static assets like images can be cached long-term.)

> **Where the infrastructure lives:** the Worker code, the R2 buckets, and the DNS/custom-domain
> setup are all defined in the **`backlot`** infrastructure repo
> (`cloudflare/workers/r2-static/`). This repo only owns the *content* of the LottoExpat site.

---

## Deploy

Publishing is one command. It **backs up** whatever is currently live, then **syncs** this repo to
the `lottoexpat-web` bucket.

### One-time setup

You need the **AWS CLI v2** (R2 speaks the S3 API) and **R2 API keys**:

1. Install AWS CLI v2 (`winget install Amazon.AWSCLI` or from aws.amazon.com/cli).
2. In Cloudflare → **R2 → Manage API Tokens**, create an **S3 Auth** token (Object Read & Write).
   You get an **Access Key ID** and **Secret Access Key**. Store them in Bitwarden.
3. Put them in your terminal (each new PowerShell session):
   ```powershell
   $env:R2_ACCESS_KEY_ID     = "<access key id>"
   $env:R2_SECRET_ACCESS_KEY = "<secret>"
   ```

### Publish

```powershell
.\scripts\deploy-r2.ps1
```

What it does:

| Step | Action |
|---|---|
| 1 | Loads your R2 keys (and clears any stray AWS SSO session token — R2 rejects those). |
| 2 | Verifies `index.html` exists. |
| 3 | **Backup:** copies the current live bucket to `eigenheim-data/lottoexpat/backups/landing/<timestamp>/`. |
| 4 | **Sync:** uploads the repo to `lottoexpat-web` (root), deleting anything removed and skipping repo metadata (`.git`, `scripts`, `*.md`, `*.ps1`). |

Then `https://lottoexpat.de` reflects your changes immediately (HTML is served no-cache).

---

## Edit the site

- Everything is in [`index.html`](index.html). Change the copy/design there.
- Adding an image or extra file? Drop it at the repo root (e.g. `og.jpg`, or an `images/` folder) and
  reference it with a normal relative/absolute path (`/og.jpg`). `deploy-r2.ps1` uploads it
  automatically (it syncs the whole repo root, minus metadata).
- Adding another page? Create `pricing/index.html` (a folder with its own `index.html`); it becomes
  `lottoexpat.de/pricing/` thanks to the Worker's directory-index behavior.

---

## Rollback

Every deploy snapshots the previous live site to
`eigenheim-data/lottoexpat/backups/landing/<timestamp>/`. To roll back, copy a snapshot back over
the live bucket:

```powershell
$R2 = "https://a2b4edd05086abb17a4e0dc18cee789f.r2.cloudflarestorage.com"
aws s3 sync "s3://eigenheim-data/lottoexpat/backups/landing/<timestamp>/" "s3://lottoexpat-web/" `
  --endpoint-url $R2 --delete
```

(Before the R2 migration this site was served by a **Cloudflare Pages** project named `landing`
connected to this GitHub repo — `landing-adm.pages.dev`. That project still exists as a deeper
fallback; re-adding `lottoexpat.de` to it would revert to the old hosting.)

---

## History

Originally static HTML deployed via a Cloudflare **Pages** project (auto-deploy on push to `main`).
Migrated to **R2 + the `eigenheim-marketing` Worker** during the AWS→Hetzner platform migration
(the `backlot` repo, Phase 7) so all marketing sites share one off-server hosting model.
