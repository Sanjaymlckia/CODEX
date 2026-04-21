Title: Zoho CRM Context Baseline

Purpose
This file reconstructs the baseline operating context for the Zoho CRM workstream inside the CODEX hub.

Known project role
Zoho CRM is being used as a commercial and relationship-management layer across KIA, MLC, and related intake/admin workflows. It is not automatically the master operational truth for all systems. In particular, for FODE, operational truth should remain in the portal/admin/sheet runtime, with CRM acting as a downstream commercial mirror where appropriate.

Known historical work
A CRM corporate import pack was previously assembled from multiple source workbooks. That build produced:

* Accounts
* Contacts
* Corporate Intelligence
* Seeded Deals
* Setup specification / runbook / audit output

Known integration themes

1. Zoho Books integration
   A key requirement is coordinated customer creation in Zoho Books. The trigger boundary and customer identity model must be carefully controlled.

2. Customer identity model
   A major open issue is whether the Books customer should be:

* Student
  or
* Parent / Sponsor / Family billing entity

This choice has upstream and downstream implications for invoicing, account duplication, payment reporting, family grouping, debt tracking, and operational clarity.

3. Closed Won / customer creation trigger
   There is a standing requirement that Customer Numbers be generated and assigned in a structured institutional format at the correct lifecycle stage, likely near or at Closed Won, subject to final business rules.

4. FODE boundary
   FODE CRM integration should remain downstream and should not become the operational brain of the admissions workflow. The portal/admin runtime and authoritative sheet remain the true operational control layer.

5. Cross-project context sources
   Relevant logic and context are scattered across:

* Zoho CRM project discussions
* marketing project discussions
* software/FODE integration discussions
* Books/customer-numbering discussions

This baseline file exists to consolidate those into one local startup reference for Codex.

Immediate use
Codex should treat this file as startup context and avoid rebuilding CRM assumptions from scratch.
