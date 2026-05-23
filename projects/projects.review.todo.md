# CodexHub Projects Review TODO

Date: 2026-05-09

## Purpose

Review current CodexHub project registry after resolver audit. Do not move folders or rewrite projects.json until each project is classified.

---

## KEEP

These paths are currently valid only when physically confirmed. The sync authority root is not equal to legacy fallback roots.

| Project | Current Valid Path | Notes |
|---|---|---|
| FODE_RUNTIME | E:\Gdrive\01_SANJAY\Codex_Sync\FODE_Runtime_1wog | Canonical synced project; git-backed |
| DATA_GOVERNANCE | D:\CODEX_PROJECTS\DATA_GOVERNANCE | Legacy fallback path; verify/migrate before use |
| CODEX_FORMS | D:\CODEX_PROJECTS\CODEX_FORMS | Legacy fallback path; verify/migrate before use |
| DHERST_Audit_Review | D:\CODEX_PROJECTS\DHERST_Audit_Review | Legacy fallback path; verify/migrate before use |
| ZOHO_CRM | D:\CODEX_PROJECTS\CODEX_CRM | Legacy alias; review later |
| ZOHO_BOOKS_KIA_FODE | D:\CODEX_PROJECTS\ZOHO_BOOKS_KIA_FODE | Legacy fallback path; verify/migrate before use |
| ZOHO_BOOKS_MLC | D:\CODEX_PROJECTS\ZOHO_BOOKS_MLC | Legacy fallback path; verify/migrate before use |
| ZOHO_CRM_INSTITUTIONAL | D:\CODEX_PROJECTS\ZOHO_CRM_INSTITUTIONAL | Legacy fallback path; verify/migrate before use |

---

## ARCHIVE / CONFIRM MISSING

These registry entries did not resolve to valid home folders after removing the unsafe CODEX_CRM fallback.

| Project | Registry Path | Status |
|---|---|---|
| MLC_MARKETING | C:\CODEX_PROJECTS\MLC_MARKETING | Historical path; not current authority |
| CAR_PRADO | C:\CODEX_PROJECTS\CAR_PRADO | Historical path; not current authority |
| GENERAL_LAB | C:\CODEX_PROJECTS\GENERAL_LAB | Historical path; not current authority |

---

## MIGRATE_TO_SYNC CANDIDATES

Consider moving later to:

E:\Gdrive\01_SANJAY\Codex_Sync

| Project | Current Path | Priority |
|---|---|---|
| CODEX_FORMS | D:\CODEX_PROJECTS\CODEX_FORMS | High |
| ZOHO_BOOKS_KIA_FODE | D:\CODEX_PROJECTS\ZOHO_BOOKS_KIA_FODE | High |
| ZOHO_BOOKS_MLC | D:\CODEX_PROJECTS\ZOHO_BOOKS_MLC | Medium |
| ZOHO_CRM_INSTITUTIONAL | D:\CODEX_PROJECTS\ZOHO_CRM_INSTITUTIONAL | Medium |
| DATA_GOVERNANCE | D:\CODEX_PROJECTS\DATA_GOVERNANCE | Medium |
| DHERST_Audit_Review | D:\CODEX_PROJECTS\DHERST_Audit_Review | Medium |

---

## ACTION RULES

1. Do not move projects until backed up.
2. Do not rewrite projects.json from preview automatically.
3. Git-backed projects require clean git status before migration.
4. Non-git projects should be git-initialized or copied with manifest before migration.
5. FODE_RUNTIME remains canonical at:
   E:\Gdrive\01_SANJAY\Codex_Sync\FODE_Runtime_1wog
6. CODEX_CRM must not be used as fallback for unrelated projects.
7. Future resolver logic must support:
   - authority root: E:\Gdrive\01_SANJAY\Codex_Sync
   - legacy discovery root: D:\CODEX_PROJECTS
   - historical discovery root: C:\CODEX_PROJECTS

---

## NEXT REVIEW

Before editing projects.json:
- inspect missing projects
- decide archive vs recreate
- decide which project migrates first
- create project-specific migration CIS
