Title: Open Decisions - Zoho CRM

1. Customer model
   Decision pending:
   Should Zoho Books customer be Student or Parent / Sponsor?

Why it matters:

* invoice ownership
* reporting
* duplicate customers
* family billing
* collections logic
* sponsor handling

2. Deal model
   Decision pending:
   Should one student enrolment equal one Deal?
   Likely yes, but exact rules must be locked.

3. Contact model
   Decision pending:
   Should parent/guardian be primary Contact while student is linked as dependent/student entity?
   This appears structurally stronger for school operations, but must match actual Zoho module usage.

4. Trigger point for Books customer creation
   Decision pending:
   When exactly is a Books customer created?
   Options may include:

* on lead qualification
* on deal creation
* on payment-ready stage
* on Closed Won

Preferred direction:
Only once commercial certainty is high enough to avoid junk customer creation.

5. Imported FODE contacts
   Decision pending:
   After FODE contacts import, what is the canonical rule for creating Deals from imported Contacts?

6. Sponsor model
   Decision pending:
   How should TVET sponsors or bulk sponsors be represented where one sponsor may pay for many students?

7. Historical rollback
   Decision pending:
   If current Books setup uses Student as Customer, what is the rollback / migration strategy to Parent as Customer, if adopted?
