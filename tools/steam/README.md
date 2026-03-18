# Steam Playtest CI/CD

This repository includes a GitHub Actions workflow that exports a Windows build and uploads it to Steam whenever `main` is updated.

## Workflow

- Build file: `.github/workflows/steam-playtest.yml`
- Upload file: `.github/workflows/steam-upload.yml`
- Triggers:
  - Build on push to `main`
  - Upload on successful build completion (`workflow_run`)

## Required GitHub Secrets

Set these in **Repository Settings -> Secrets and variables -> Actions**:

- `STEAM_APP_ID` (your playtest app ID)
- `STEAM_DEPOT_ID_WINDOWS` (Windows depot ID in Steamworks)
- `STEAM_BUILDER_USERNAME` (Steam build account username)
- `STEAM_BUILDER_PASSWORD` (Steam build account password)
- `STEAM_TOTP_SECRET` (Steam shared secret used to generate TOTP login codes)

## Publish target

Uploads run app builds without setting a live branch (`setlive` is omitted).
