# egregor-share API (v0.2.0)

Filesystem + system + subsystem management API for the **erkamen lab** (pi & nuk). Every machine
runs its own instance; the home agent drives each directly, and instances can push files to each
other via `/api/send`. **LAN-only — never expose via tailscale funnel.**

## Machines
| Name | Base URL | Shared dir |
|------|----------|-----------|
| **pi** (`familliar`) | `http://192.168.0.11:7777` | `/home/erkamen/shared` |
| **nuk** | `http://192.168.0.229:7777` (fallback `http://192.168.0.230:7777`) | (its own shared) |

Same API on both. **Auth: none configured** — all endpoints open on the LAN (set `token` in
`~/.erkamen-watcher/config.json` or `EGREGOR_SHARE_TOKEN` to require it on mutations).

## Conventions
- `path` query/body args are **absolute on the target machine** (e.g. `/home/erkamen/x`).
- The `/api/shared*` namespace is **sandboxed** to the machine's shared dir and is **path-style**
  (`/api/shared/sub/file`), so it's the route to use for URLs that append names (e.g. Addressables).
- Responses are JSON unless streaming a file. Errors: `{ "error": <message> }` with a 4xx/5xx status.
- `exec`/`service` run as the service user (`erkamen`), which has **passwordless sudo** — pass
  `sudo:true` to elevate.

## Endpoints
| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api` | no | This document (`?format=html` for a page). |
| GET | `/api/info` | no | Machine identity, version, peers, capabilities, uptime. |
| GET | `/api/metrics` | no | Live CPU/mem/disk/io/net/temps/gpu sample. |
| GET | `/api/procs` | no | Watched systemd services + top processes. |
| GET | `/api/fs?path=<abs>` | no | Browse a directory (read-only): name/type/size/mtime. |
| GET | `/api/file?path=<abs>[&download]` | no | Read/stream any file. |
| PUT | `/api/file?path=<abs>` | yes* | Write/overwrite a file anywhere. Body = raw bytes. **Parent dirs auto-created.** |
| DELETE | `/api/file?path=<abs>` | yes* | Delete a file or directory (recursive). Refuses `/`. |
| POST | `/api/mkdir` | yes* | `{path}` — create a directory (recursive). |
| POST | `/api/move` | yes* | `{from,to}` — move/rename. |
| GET | `/api/shared[?path=<rel>]` | no | List the shared dir (sandboxed). |
| GET/PUT/DELETE | `/api/shared/<rel>` | PUT/DELETE* | Get/upload/delete a file in the shared dir. Subdirs auto-created on PUT. |
| POST | `/api/send` | yes* | `{path,peer,as?}` — push a shared file to a peer's shared dir. |
| POST | `/api/service` | yes* | `{unit,action,scope}` — control a systemd unit (`scope:user`/`system`). |
| GET | `/api/logs?unit=<n>&lines=<n>&scope=system\|user` | no | Tail journalctl for a unit. |
| POST | `/api/exec` | yes* | `{cmd,args,cwd?,timeout?,sudo?,shell?}` — run a command. `shell:true` = `sh -c`. Returns `{ok,code,stdout,stderr}`. |
| GET/POST | `/api/unity` | GET no / POST yes* | Unity accelerator: status/cache (GET); `{action:start\|stop\|restart\|logs}` (POST). |
| GET | `/api/storage` | no | `df` of all mounts + `du` of largest dirs in /mnt/cache & /home. |
| GET | `/api/pardes` | no | Proxy/summary of the local pardes library API (`:3001`). |

\* "auth: yes" only enforces when a token is configured; currently open on the LAN.

## Subsystems
- **pardes** — Flibusta book library (~1.1 TB at `/mnt/cache/library`). API `http://<host>:3001`, docs `:3001/api`.
- **unity-accelerator** — docker `unity-accelerator`; cache port `10080`, dashboard `8080`, cache dir
  `/mnt/cache/unity-accelerator/cachedb`.

## Storage note (pi)
`/mnt/cache` = **1.8 TB HDD, ~662 GB free** (use for big content). Root `/` only ~11 GB free.

## Examples
```bash
curl http://192.168.0.11:7777/api/info
curl 'http://192.168.0.11:7777/api/fs?path=/home/erkamen'
curl -T local.bin http://192.168.0.11:7777/api/shared/sub/local.bin          # upload (path-style)
curl -X PUT 'http://192.168.0.11:7777/api/file?path=/mnt/cache/x/y.bin' --data-binary @y.bin
curl -X DELETE 'http://192.168.0.11:7777/api/file?path=/mnt/cache/x'           # recursive
curl -X POST http://192.168.0.11:7777/api/mkdir -H 'Content-Type: application/json' -d '{"path":"/mnt/cache/x"}'
curl -X POST http://192.168.0.11:7777/api/exec  -H 'Content-Type: application/json' -d '{"cmd":"df","args":["-h"]}'
```

## maradel-face usage (this project)
Addressables bundles are hosted on the pi HDD via a symlink so the path-style route serves them:
- `ln -s /mnt/cache/addressables /home/erkamen/shared/addressables`
- **Upload:** `PUT /api/shared/addressables/<BuildTarget>/<file>` (the `Maradel ▸ Build` pipeline /
  `tool/upload-addressables.ps1` do this).
- **Serve / Addressables RemoteLoadPath:** `http://192.168.0.11:7777/api/shared/addressables/[BuildTarget]`
- Voice backend (separate) lives on the nuk at `:9100` (`/voice/stream`, `voice:chunk` socket).
