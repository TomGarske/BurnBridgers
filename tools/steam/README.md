# Ironwake — Steam Playtest CI/CD

This repository includes GitHub Actions workflows that export a **Windows** **Ironwake** build (`Ironwake.exe`) and upload it to Steam whenever `main` is updated.

## Workflow

- Build: `.github/workflows/steam-playtest.yml` (workflow name: **Ironwake Steam Build (Windows)**)
- Upload: `.github/workflows/steam-upload.yml` (workflow name: **Ironwake Steam Upload**)
- Triggers:
  - Build on push to `main`
  - Upload on successful build completion (`workflow_run`)
- Build artifact name: `ironwake-windows-steam-build`

## Required GitHub Secrets

Set these in **Repository Settings -> Secrets and variables -> Actions**:

- `STEAM_APP_ID` (your playtest app ID)
- `STEAM_DEPOT_ID_WINDOWS` (Windows depot ID in Steamworks)
- `STEAM_BUILDER_USERNAME` (Steam build account username)
- `STEAM_BUILDER_PASSWORD` (Steam build account password)
- `STEAM_TOTP_SECRET` (Steam shared secret used to generate TOTP login codes)

## Publish target

Uploads run app builds without setting a live branch (`setlive` is omitted).
