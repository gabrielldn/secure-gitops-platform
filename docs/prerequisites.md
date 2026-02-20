# Prerequisites

## Host baseline

- WSL2 Ubuntu 24.04.
- Docker Engine installed and running.
- Ansible available.
- `make` available (or run Ansible bootstrap command directly).
- Internet access for chart/image downloads.

## Recommended WSL profile (`full`)

Create `%UserProfile%\\.wslconfig` on Windows:

```ini
[wsl2]
memory=20GB
processors=10
swap=8GB
localhostForwarding=true
```

Then run `wsl --shutdown` from Windows PowerShell and reopen Ubuntu.

Templates are available in:

- `scripts/wslconfig-full.template`
- `scripts/wslconfig-light.template`

## Fallback profile (`light`)

If host memory is constrained, use:

```bash
make doctor PROFILE=light
make up PROFILE=light
```

`light` is the default profile for local convergence and acceptance tests.

## Docker group access

`make bootstrap` adds your Linux user to the `docker` group. Restart your shell/session after bootstrap.

## Falco in WSL

Falco is best-effort on WSL due to kernel/eBPF constraints.

- If Falco works: keep it enabled.
- If Falco fails: keep Trivy Operator + policies + audit/alerts as mandatory fallback.
- `make verify` marks Falco as conditional in WSL.
