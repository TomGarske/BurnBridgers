# Ironwake — Steam Playtest CI/CD

This repository includes GitHub Actions workflows that export **Windows** and **Linux** (Steam Deck) builds of Ironwake and upload them to Steam whenever `main` is updated.

## Workflow

- Build (Windows): `.github/workflows/steam-playtest.yml` — **Ironwake Steam Build (Windows)**
- Build (Linux/Steam Deck): `.github/workflows/steam-playtest-linux.yml` — **Ironwake Steam Build (Linux / Steam Deck)**
- Upload: `.github/workflows/steam-upload.yml` — **Ironwake Steam Upload**
- Triggers:
  - Both builds trigger on push to `main`
  - Upload triggers on successful completion of either build workflow
  - Upload downloads the latest artifact from both platforms and uploads them as separate depots
- Build artifact names:
  - `ironwake-windows-steam-build`
  - `ironwake-linux-steam-build`

## Required GitHub Secrets

Set these in **Repository Settings -> Secrets and variables -> Actions**:

- `STEAM_APP_ID` (your playtest app ID)
- `STEAM_DEPOT_ID_WINDOWS` (Windows depot ID in Steamworks)
- `STEAM_DEPOT_ID_LINUX` (Linux depot ID in Steamworks — for Steam Deck / SteamOS)
- `STEAM_BUILDER_USERNAME` (Steam build account username)
- `STEAM_BUILDER_PASSWORD` (Steam build account password)
- `STEAM_TOTP_SECRET` (Steam shared secret used to generate TOTP login codes)

## Steam Deck / SteamOS

The Linux build targets x86_64 and is compatible with Steam Deck (SteamOS 3.x).
In Steamworks, create a Linux depot and set its launch option OS to "Linux".
Steam Deck will automatically download the Linux depot when the game is installed.

## Publish target

Uploads run app builds without setting a live branch (`setlive` is omitted).
