# ============================================================================
# deploy-r2.ps1 - Deploy the LottoExpat landing site to Cloudflare R2
# ============================================================================
# This is a STATIC single-file site (index.html, all CSS/JS inline). There is
# NO build step - the repo root IS the site. It is served by the Cloudflare
# Worker `eigenheim-marketing` directly from the R2 bucket `lottoexpat-web`
# (bucket ROOT). See README.md for how/why this works.
#
# One command: backup the current live bucket, then sync the repo to it.
#
# Usage:  .\scripts\deploy-r2.ps1     (run from anywhere; paths are resolved)
# Requires: aws cli v2, and R2 S3 credentials in the environment:
#   $env:R2_ACCESS_KEY_ID     = "<r2 access key id>"
#   $env:R2_SECRET_ACCESS_KEY = "<r2 secret>"
#   (optional) $env:CF_ACCOUNT_ID = "a2b4edd05086abb17a4e0dc18cee789f"
# Create the R2 keys in Cloudflare -> R2 -> Manage API Tokens. Store in Bitwarden.
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CF_ACCOUNT_ID = if ($env:CF_ACCOUNT_ID) { $env:CF_ACCOUNT_ID } else { "a2b4edd05086abb17a4e0dc18cee789f" }
$R2_ENDPOINT   = "https://$CF_ACCOUNT_ID.r2.cloudflarestorage.com"
$R2_BUCKET     = "lottoexpat-web"                              # served at ROOT by the Worker
$R2_BACKUP_URI = "s3://eigenheim-data/lottoexpat/backups/landing"  # snapshots, off the live bucket
$SITE_DIR      = Join-Path $PSScriptRoot ".."                 # repo root = the site

# --- Step 1: R2 credentials (NOT AWS SSO) -----------------------------------
Write-Host "`n[1/4] Checking R2 credentials..." -ForegroundColor Cyan
if (-not $env:R2_ACCESS_KEY_ID -or -not $env:R2_SECRET_ACCESS_KEY) {
    Write-Host "R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY are not set." -ForegroundColor Red
    Write-Host "Set them (Cloudflare R2 -> Manage API Tokens -> S3 keys) and re-run." -ForegroundColor Red
    exit 1
}
# aws cli reads AWS_* - map the R2 creds for this session, and CLEAR any AWS SSO
# session token / profile: R2 rejects requests carrying X-Amz-Security-Token
# (400 InvalidArgument), which is exactly what a leftover SSO token adds.
$env:AWS_ACCESS_KEY_ID     = $env:R2_ACCESS_KEY_ID
$env:AWS_SECRET_ACCESS_KEY = $env:R2_SECRET_ACCESS_KEY
$env:AWS_DEFAULT_REGION    = "auto"
Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:\AWS_PROFILE       -ErrorAction SilentlyContinue
Write-Host "R2 endpoint: $R2_ENDPOINT  (bucket: $R2_BUCKET)" -ForegroundColor Green

# --- Step 2: Verify the site ------------------------------------------------
if (-not (Test-Path (Join-Path $SITE_DIR "index.html"))) {
    Write-Host "index.html not found at repo root ($SITE_DIR)." -ForegroundColor Red
    exit 1
}
$fileCount = (Get-ChildItem -File $SITE_DIR).Count
Write-Host "`n[2/4] Site ready at $SITE_DIR (index.html present, $fileCount root files)" -ForegroundColor Cyan

# --- Step 3: Backup current bucket contents (R2 -> R2) ----------------------
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
Write-Host "`n[3/4] Backing up current s3://$R2_BUCKET/ to $R2_BACKUP_URI/$timestamp/ ..." -ForegroundColor Cyan
aws s3 sync "s3://$R2_BUCKET/" "$R2_BACKUP_URI/$timestamp/" --endpoint-url $R2_ENDPOINT --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "Backup failed - aborting deploy." -ForegroundColor Red
    exit 1
}
Write-Host "Backed up to $R2_BACKUP_URI/$timestamp/" -ForegroundColor Green

# --- Step 4: Sync the site to the R2 bucket ROOT ----------------------------
# The repo root is the site. Exclude repo metadata / tooling so only real site
# files land in the bucket. Content-Type is inferred from the file extension by
# the aws cli; Cache-Control is set by the Worker at serve time. --exact-timestamps
# avoids stale objects; --delete prunes files removed from the repo.
Write-Host "`n[4/4] Syncing site -> s3://$R2_BUCKET/ ..." -ForegroundColor Cyan
aws s3 sync $SITE_DIR "s3://$R2_BUCKET/" `
    --endpoint-url $R2_ENDPOINT `
    --delete `
    --exact-timestamps `
    --exclude ".git/*" `
    --exclude ".github/*" `
    --exclude "scripts/*" `
    --exclude "*.md" `
    --exclude "*.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "R2 sync failed." -ForegroundColor Red
    exit 1
}

Write-Host "`nDeployed to s3://$R2_BUCKET/ - live via the Cloudflare Worker at https://lottoexpat.de" -ForegroundColor Green
Write-Host "HTML is served no-cache by the Worker, so edits go live immediately." -ForegroundColor DarkGray
Write-Host "If the edge shows stale content, purge the Cloudflare cache for lottoexpat.de." -ForegroundColor DarkGray
