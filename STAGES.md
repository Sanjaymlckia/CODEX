# Stage Governance

Stages must stay small, stable, and operationally meaningful.

## Distinction

- Lifecycle states are institutional truth.
- Pipeline stages are workflow execution.
- Actions are events or tasks, not stages.

## Approved Pipeline Stage Set

- New To MLCKIA.
- Contacted.
- Documents Pending.
- Payment Pending.
- Enrolled.
- Closed Lost.

## Guardrails

- Do not create a new stage for every message, reminder, invoice, or operator action.
- Prefer action logs, telemetry, or queue metadata for operational events.
- Avoid stage explosion unless reporting or routing fails without a new stage.
