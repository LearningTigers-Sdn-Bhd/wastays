# Folio: Refund Lifecycle

## Status

Basic refund request lifecycle is implemented. Enterprise multi-stage approval and deeper gateway reconciliation remain future work.

## Purpose

Connects guest or staff refund requests to administrative approval and immutable folio ledger posting, so completed refunds are visible to night audit, reporting, and financial audit trails.

## Key Files

- `app/models/refund_request.rb`
- `app/models/refund_policy.rb`
- `app/services/refunds/submit_request.rb`
- `app/services/refunds/eligibility.rb`
- `app/services/folios/record_refund.rb`
- `app/services/hotel_ops/evaluate_night_audit.rb`
- `app/controllers/guest/refund_requests_controller.rb`
- `app/controllers/hotel_portal/refund_requests_controller.rb`
- `app/controllers/admin/refund_requests_controller.rb`
- `app/mailers/refund_mailer.rb`
- `spec/models/refund_request_spec.rb`
- `spec/services/folios/record_refund_spec.rb`
- `spec/requests/guest/refund_requests_spec.rb`
- `spec/requests/hotel_portal/refund_requests_spec.rb`
- `spec/requests/admin/refund_requests_spec.rb`

## Rules Made So Far

- A booking can have one refund request.
- Refund requests move through `pending`, `approved`, `rejected`, and `completed` states.
- Guest refund submission cancels eligible confirmed bookings and creates a pending refund request using the active refund policy.
- Rejected guest refund requests can be resubmitted and returned to `pending`.
- Hotel portal staff can create eligible refund requests for bookings.
- Admin users can approve, reject, and complete refund requests.
- Completing a refund posts an immutable folio transaction through `Folios::RecordRefund` when the booking has a folio.
- Folio refund postings use `transaction_type: payment`, `category: refund`, and a negative amount.
- Refund folio postings include `metadata["refund_request_id"]` so they can be traced and deduplicated.
- `Folios::RecordRefund` is idempotent and returns the existing refund transaction if the refund was already recorded.
- Refund postings on closed or prior business dates use a system-level night-audit override with correction context.
- Night audit evaluation blocks on completed refund requests that have not been synced to the folio as `refund_not_synced`.
- Completing a refund records booking audit history and sends the guest completion email.

## Known Follow-Ups

- Add multi-stage approval for high-value refunds.
- Link refund ledger entries to original payment gateway identifiers in staff-facing reconciliation views.
- Decide whether refund completion should execute the payment-gateway refund automatically or remain an administrative/manual settlement step.
- Expose clearer staff guidance when a completed refund is blocked by `refund_not_synced` during night audit.
