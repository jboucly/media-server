# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Self-hosted media server defined entirely in a single [docker-compose.yml](docker-compose.yml). There is no application code, build, lint, or test step. Comments in the compose file are in French.

## Host environment

The stack runs inside a **Proxmox container (LXC)**, not on bare metal or a full VM. The Docker host is therefore the LXC, and some requirements depend on the Proxmox side (container config on the Proxmox node), not on this repo:

- Docker inside LXC needs the `nesting` (and usually `keyctl`) features enabled on the container.
- Gluetun needs `/dev/net/tun`, which must be passed through to the LXC from the Proxmox host.
- `/mnt/media` is a path inside the LXC, typically a bind mount from the Proxmox host storage. Its ownership must match `PUID/PGID=1000` as seen from inside the container (watch UID mapping if the LXC is unprivileged).
- `network_mode: host` on Plex means the LXC's network interface, so Plex is reachable on the LXC's IP on the LAN.

When troubleshooting VPN, permission, or device errors, consider the LXC/Proxmox configuration before changing the compose file.

## Commands

```bash
cp .env.example .env          # then fill in secrets
docker compose config         # validate the compose file and env interpolation
docker compose up -d          # start the stack
docker compose up -d <svc>    # (re)create a single service after editing it
docker compose logs -f <svc>
```

## Architecture

- **gluetun** — Mullvad WireGuard VPN (Switzerland servers). Requires `/dev/net/tun` and `NET_ADMIN`.
- **qbittorrent** — uses `network_mode: "service:gluetun"`, so all torrent traffic goes through the VPN and it has no network of its own. Its ports (WebUI 8080, torrent 6881 tcp/udp) are therefore published on the **gluetun** service, not on qbittorrent. Adding/changing qBittorrent ports means editing gluetun. It waits for gluetun to be healthy.
- **plex** — `network_mode: host` (needed for LAN discovery), so it has no `ports:` mapping. Remote access for Plexamp is via **cloudflared** (Cloudflare Tunnel, configured remotely through `CLOUDFLARE_TUNNEL_TOKEN`).
- **slskd** (Soulseek client) — also `network_mode: "service:gluetun"`; its web UI port 5030 is published on gluetun, and other containers reach it at `http://gluetun:5030`. Downloads and incomplete dirs are both under `/mnt/media/downloads/` (must stay on the same volume so slskd renames instead of copying).
- **pickarr** ([gitlab.com/dhmetha/pickarr](https://gitlab.com/dhmetha/pickarr)) — image `ghcr.io/jboucly/pickarr`, built from upstream by the manual "pickarr image" workflow of [github.com/jboucly/discoverr](https://github.com/jboucly/discoverr) and published as a **private** GHCR package (the Docker host must be logged in to ghcr.io). Turns a Spotify/YouTube/SoundCloud link into a tagged file in `/mnt/media/Musiques/pickarr` (a single folder: it cannot split by quality like the existing `Musiques/lossless` and `Musiques/Standard`), sourcing audio from slskd first, then yt-dlp, then triggers a Plex scan. Runs as UID 1000 (non-root), so its `/opt/appdata/pickarr` bind mount must be owned by 1000. Reaches Plex via `host.docker.internal:32400` (`extra_hosts: host-gateway`) because Plex is on the host network. Web UI on port 8090.
- **discoverr** (image `ghcr.io/jboucly/discoverr`) — weekly "Découvertes de la semaine". See the dedicated section below.
- **\*arr stack** — sonarr (8989, series), radarr (7878, movies), lidarr (8686, music), prowlarr (9696, indexers). These are not behind the VPN.

Shared conventions across services: `PUID/PGID=1000`, `TZ=Europe/Paris`, linuxserver.io images, a named volume `<service>_config` for `/config`, and the host path `/mnt/media` mounted at `/media` (same path in every container so download/import paths match between qBittorrent and the *arr apps). A new service's config volume must also be declared under the top-level `volumes:`.

## Secrets

Required in `.env` (see [.env.example](.env.example)): `MULLVAD_WIREGUARD_PRIVATE_KEY`, `MULLVAD_WIREGUARD_ADDRESS`, `CLOUDFLARE_TUNNEL_TOKEN`, `PLEX_CLAIM`, plus the Pickarr/slskd variables (`PLEX_TOKEN`, `SLSKD_API_KEY` shared by both, etc.). The `mullvad_wireguard_macos_ch_zrh/` directory (raw Mullvad configs) is gitignored.

## discoverr

discoverr lives in its own repo ([github.com/jboucly/discoverr](https://github.com/jboucly/discoverr), docs and code there); this repo only deploys its image. It uses the **main pickarr instance** (`PICKARR_URL=http://pickarr:8080`, `PICKARR_API_KEY`) and sends each pick with `subfolder=Decouvertes`, so discoveries land in `Musiques/pickarr/Decouvertes`. These must stay consistent: `PICKARR_LIBRARY_SUBDIR=pickarr`, `PICKARR_SUBFOLDER=Decouvertes`, `DISCOVERY_SUBDIR=pickarr/Decouvertes`, and `ALLOW_DELETE_IN_PICKARR_LIBRARY=true` (otherwise the weekly cleanup deletes nothing). The cleanup only ever deletes inside `DISCOVERY_SUBDIR`.
