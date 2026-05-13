# Operational Pipeline Stages

Pipeline stages are the workflow execution layer. They describe the current operational handling position, not the long-term institutional lifecycle state.

## Canonical Pipeline Stages

| Stage | Meaning |
| --- | --- |
| New To MLCKIA | New intake or first known operational record. |
| Contacted | Initial contact has been made. |
| Documents Pending | Required documents are incomplete or missing. |
| Payment Pending | Payment or invoice completion is pending. |
| Enrolled | Operational enrolment workflow completed. |
| Closed Lost | Opportunity or application did not proceed. |

## Optional Later Stages

- Deferred.
- Orientation.
- Ready For LMS.
- Fee Paid.

Do not add optional stages until a concrete operational failure proves the need.

## Rule

Operational actions != stages.

Correct: Stage: Payment Pending. Action: Send Invoice.

Wrong: Stage: Reminder Sent. Stage: Invoice Sent.
