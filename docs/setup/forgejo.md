# Forgejo and runner setup

How the local Forgejo server and its runner are installed and configured on
the development machine (plan section 8; environment in section 9.2). The
goal is that the whole local CI setup can be rebuilt from this page.

Every step here was done on Ubuntu 26.04 in WSL2. Each pitfall below cost
real time once; the fixes are recorded so they are not rediscovered.

Status: Forgejo and the runner are installed and running. Accounts, the
repository import, branch protection, the first workflow and the GitHub
mirror are still to do (section 6) and will be added here as they are done.

## 1. Overview

| Item | Value |
|---|---|
| Forgejo | 17.0.1, binary `/usr/local/bin/forgejo` |
| Forgejo user | `forgejo` (system user), home `/var/lib/forgejo` |
| Configuration | `/etc/forgejo/app.ini` (owner `root`, group `forgejo`, directory mode 770) |
| Work directory | `/var/lib/forgejo` (data under `/var/lib/forgejo/data`) |
| Database | SQLite |
| URL | `http://localhost:3000` (also reachable from the Windows browser) |
| Runner | v13.1.0, binary `/usr/local/bin/forgejo-runner` |
| Runner user | `forgejo-runner` (system user), home `/var/lib/forgejo-runner` |
| Runner configuration | `/var/lib/forgejo-runner/config.yml` (mode 600, holds the runner token) |
| Runner label | `wsl-host:host` (jobs run directly on this machine) |
| Control script | `forgejo-ctl` (source: `tools/forgejo-ctl` in this repository) |
| Logs | `/var/lib/forgejo/log/forgejo-ctl.log`, `/var/lib/forgejo-runner/runner.log` |

Versions are recorded in `docs/evidence/m0/tool_versions.txt`.

## 2. Downloading binaries safely

Two downloads (the runner and the PlantUML jar) failed silently during setup:
the server answered with an error page, which was saved under the program's
name. Always download with `curl -fL` and check the result before installing:

```bash
curl -fL -o <file> "<exact link to the release file>"
file <file>          # a program must say "ELF 64-bit"; a jar "Java archive" or "Zip"
```

- `-L` follows redirects to where the file is actually stored.
- `-f` makes curl fail on an HTTP error instead of saving the error page.

## 3. Forgejo

### 3.1 Installation

> **To be completed:** how Forgejo 17.0.1 was installed (binary download,
> `forgejo` user creation, initial `app.ini`, first-run web setup). Record the
> steps the next time they are repeated, or from notes if available.

### 3.2 Pitfall: the forgejo user's home directory

**Symptom:** Forgejo starts and exits within seconds. In the foreground it ends with:

```
[F] forgejo.org/modules/ssh.Init(ctx) failed: rewrite authorized_keys failed: mkdir /nonexistent: permission denied
```

**Cause:** the `forgejo` system user was created with the placeholder home
`/nonexistent` (the default for system users). On start-up Forgejo rewrites
`~/.ssh/authorized_keys` for the user it runs as, and cannot create
`/nonexistent/.ssh`.

**Fix:** give the user its work directory as home:

```bash
sudo usermod -d /var/lib/forgejo forgejo
getent passwd forgejo        # the home field must now be /var/lib/forgejo
```

When creating the user from scratch, give it a home directly, e.g.
`useradd --system --home-dir /var/lib/forgejo ... forgejo`.

### 3.3 Running Forgejo by hand (diagnostics)

To see Forgejo's own messages when something is wrong:

```bash
cd /
sudo -u forgejo /usr/local/bin/forgejo web --config /etc/forgejo/app.ini
```

Stop it with Ctrl+C. `app.ini` contains secrets: never copy it into the
repository or paste it into a chat.

## 4. The runner

### 4.1 Runner user

```bash
sudo useradd --system --create-home --home-dir /var/lib/forgejo-runner \
  --shell /bin/bash forgejo-runner
```

The runner runs as its own user, not as the owner: CI must not depend on the
owner's account, and a bad job is limited to what this user can do.

### 4.2 Registration (current method)

**Pitfall:** `forgejo-runner register` is deprecated. With a token from
Forgejo's "Create new runner" dialog it fails with
`runner registration token not found`. Current runners are registered by
putting the connection into the runner's configuration file instead.

1. In Forgejo: **Site Administration → Actions → Runners → Create new runner**.
   Forgejo displays a **UUID** and a **token**. The token is a secret.
2. Generate the default configuration, as the runner user, readable only by it:

   ```bash
   sudo -u forgejo-runner -H bash -c 'cd /var/lib/forgejo-runner && \
     forgejo-runner generate-config > config.yml; echo "exit=$?"'
   sudo chmod 600 /var/lib/forgejo-runner/config.yml
   sudo ls -l /var/lib/forgejo-runner/config.yml   # several kilobytes, mostly comments
   ```

   Do not open the file in an editor before generating it: the editor would
   create an empty file without the sections to edit.
3. Edit it: `sudo -u forgejo-runner nano /var/lib/forgejo-runner/config.yml`.
   Change the existing sections (do not add second copies; spaces, not tabs):

   ```yaml
   runner:
     labels:
       - wsl-host:host

   server:
     connections:
       forgejo:
         url: http://localhost:3000/
         uuid: <UUID from Forgejo>
         token: <token from Forgejo>
   ```

### 4.3 The `host` label

`wsl-host:host` makes jobs with `runs-on: wsl-host` run directly on this
machine, without a container, so they can use the locally installed tools
(GHDL now, Vivado from M2). There is no isolation: a job can do anything the
`forgejo-runner` user can do.

## 5. Starting and stopping: `forgejo-ctl`

Install or update from the repository:

```bash
sudo install -m 755 tools/forgejo-ctl /usr/local/bin/forgejo-ctl
```

| Command | Effect |
|---|---|
| `forgejo-ctl start` | Start Forgejo, wait until it answers, then start the runner |
| `forgejo-ctl stop` | Stop the runner, then Forgejo |
| `forgejo-ctl restart` | Stop, then start |
| `forgejo-ctl status` | Report both; exit status 0 only if everything is healthy |
| `forgejo-ctl logs [forgejo\|runner] [lines]` | Show the end of a log |

Design points, each the answer to a problem met during setup:

- Output goes to log files, never discarded; on a failed start the end of the
  log is shown.
- `start` succeeds only when Forgejo's own process is alive **and** it answers
  at `/api/healthz`; it refuses to start if something else holds the port.
- `sudo` runs in the foreground, where its password is cached. Ubuntu caches
  `sudo` per terminal, so a detached `sudo` would need the password again and
  fail silently.
- The services are detached inside `sudo` with `setsid --fork`, so nothing
  holds the terminal (Ubuntu's `sudo` uses `use_pty`) and no parent process is
  left behind.
- The runner counts as set up when its `config.yml` exists.

## 6. Still to do (M0)

Added here as each is done:

1. Owner account and the agents' push account (if chosen, plan O-6).
2. Import the repository from GitHub.
3. Branch protection on `main`: required checks, linear history, no force
   pushes, only the owner merges.
4. First workflow (`.forgejo/workflows/`), running the gates on `wsl-host`.
   Python tools come from a pinned `requirements.txt`, not the owner's `.venv`;
   checkout with plain `git` or a system-wide Node.js (the owner's `nvm` Node.js
   is not visible to the runner user).
5. Push mirror to GitHub, triggered by the owner.
6. Repoint the local clone's `origin` to Forgejo.
7. Backups of `/var/lib/forgejo`.
