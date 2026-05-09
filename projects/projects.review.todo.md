# CodexHub Projects Review TODO

Date: 2026-05-09

## Purpose

Review current CodexHub project registry after resolver audit. Do not move folders or rewrite projects.json until each project is classified.

---

## KEEP

These paths are currently valid.

| Project | Current Valid Path | Notes |
|---|---|---|
| FODE_RUNTIME | E:\Gdrive\01 SANJAY\Codex_Sync\FODE_Runtime_1wog | Canonical synced project; git-backed |
| DATA_GOVERNANCE | D:\CODEX_PROJECTS\DATA_GOVERNANCE | Valid home path; git-backed |
| CODEX_FORMS | D:\CODEX_PROJECTS\CODEX_FORMS | Valid home path; not git-backed |
| DHERST_Audit_Review | D:\CODEX_PROJECTS\DHERST_Audit_Review | Valid home path; not git-backed |
| ZOHO_CRM | D:\CODEX_PROJECTS\CODEX_CRM | Legacy alias; review later |
| ZOHO_BOOKS_KIA_FODE | D:\CODEX_PROJECTS\ZOHO_BOOKS_KIA_FODE | Valid home path; not git-backed |
| ZOHO_BOOKS_MLC | D:\CODEX_PROJECTS\ZOHO_BOOKS_MLC | Valid home path; not git-backed |
| ZOHO_CRM_INSTITUTIONAL | D:\CODEX_PROJECTS\ZOHO_CRM_INSTITUTIONAL | Valid home path; not git-backed |

---

## ARCHIVE / CONFIRM MISSING

These registry entries did not resolve to valid home folders after removing the unsafe CODEX_CRM fallback.

| Project | Registry Path | Status |
|---|---|---|
| MLC_MARKETING | C:\CODEX_PROJECTS\MLC_MARKETING | Missing on home machine |
| CAR_PRADO | C:\CODEX_PROJECTS\CAR_PRADO | Missing on home machine |
| GENERAL_LAB | C:\CODEX_PROJECTS\GENERAL_LAB | Missing on home machine |

---

## MIGRATE_TO_SYNC CANDIDATES

Consider moving later to:

E:\Gdrive\01 SANJAY\Codex_Sync

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
   E:\Gdrive\01 SANJAY\Codex_Sync\FODE_Runtime_1wog
6. CODEX_CRM must not be used as fallback for unrelated projects.
7. Future resolver logic must support:
   - home root: D:\CODEX_PROJECTS
   - office root: C:\CODEX_PROJECTS
   - sync root: E:\Gdrive\01 SANJAY\Codex_Sync

---

## NEXT REVIEW

Before editing projects.json:
- inspect missing projects
- decide archive vs recreate
- decide which project migrates first
- create project-specific migration CIS
