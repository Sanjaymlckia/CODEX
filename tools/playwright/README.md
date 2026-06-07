## FODE Playwright Acceptance Harness

Location:
`E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub\tools\playwright`

Purpose:
- FODE Runtime smoke testing against the current baseline
- ACP Phase 1 OPS Communications label verification
- Legacy Admin and OPS surface health verification
- Queue/startup health and click-safety inspection
- read-only browser evidence
- zero FODE runtime source, Apps Script, sheet, version, or deployment changes

### Setup

```powershell
cd E:\Gdrive\01_SANJAY\Codex_Sync\CodexHub\tools\playwright
npm install
npx playwright install chromium
Copy-Item .env.example .env
```

Edit `.env`:

```text
FODE_ADMIN_URL=https://script.google.com/macros/s/YOUR_ADMIN_DEPLOYMENT/exec
FODE_STUDENT_URL=https://script.google.com/macros/s/YOUR_STUDENT_DEPLOYMENT/exec
EXPECTED_VERSION=r214
EXPECTED_VERSION_NUMBER=214
```

Supported URL aliases:

```text
FODE_ADMIN_BASE_URL=...
FODE_STUDENT_BASE_URL=...
FODE_ADMIN_OPS_URL=...
FODE_ADMIN_WHOAMI_URL=...
FODE_STUDENT_WHOAMI_URL=...
```

### Commands

Capture Admin auth:

```powershell
npm run auth:admin
```

Run baseline smoke:

```powershell
npm run test:smoke
```

Run ACP Phase 1 OPS labels:

```powershell
npm run test:ops-labels
```

Run legacy Admin health:

```powershell
npm run test:legacy-admin
```

Run OPS surface health:

```powershell
npm run test:ops-surface
```

Run OPS queue health:

```powershell
npm run test:ops-queue-health
```

Run OPS startup health:

```powershell
npm run test:ops-startup
```

Run click-safety inspection:

```powershell
npm run test:click-safety
```

Run all read-only surface checks:

```powershell
npm run test:all-surfaces
```

### Evidence

Evidence is written to timestamped folders:

```text
reports/<timestamp>-auth-capture/
reports/<timestamp>-admin-whoami/
reports/<timestamp>-student-whoami/
reports/<timestamp>-admin-ops/
reports/<timestamp>-ops-communications-labels/
reports/<timestamp>-legacy-admin-health/
reports/<timestamp>-ops-surface-health/
reports/<timestamp>-ops-queue-health/
reports/<timestamp>-ops-startup/
reports/<timestamp>-click-safety/
```

Evidence includes screenshots, JSON captures, `RUN_SUMMARY.md`, and `RUN_SUMMARY.json`.

### Safety Rules

- Do not click send controls.
- Do not click export controls.
- Do not run mutation actions.
- Inspect dangerous controls through labels, disabled state, and explanatory/gating text only.
- Do not deploy from this harness.
- Do not create Apps Script versions from this harness.
- Do not modify FODE runtime source from this harness.

### Notes

- `playwright.config.ts` does not define global `storageState`.
- Admin auth state is used only by authenticated Admin/OPS specs.
- Admin OPS route is forced through `?view=ops`.
- Whoami smoke checks fail fast on missing runtime identity, mismatch, Student Portal, `missingToken`, or wrong route signals.
