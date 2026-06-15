# Financial Contracts: Financial Observability

## Status

Completed May 21, 2026.

## Purpose

Provides professional-grade oversight by automatically detecting and alerting on ledger discrepancies, audit lags, and potential fraud patterns.

## Key Files

- `app/models/hotel_team_config.rb`
- `app/services/financial_controls/evaluate_anomalies.rb`
- `app/mailers/finance_alert_mailer.rb`
- `app/jobs/financial_observability_job.rb`
- `spec/services/financial_controls/evaluate_anomalies_spec.rb`

## Rules Made So Far

- **Automated Detection:** The system automatically evaluates hotels for:
  - **Unbalanced Folios:** Closed bookings with a non-zero outstanding balance.
  - **Audit Sync Lags:** Business dates that have failed to roll and are > 2 days behind reality.
  - **Override Abuse:** High volumes (> 5) of closed-date overrides within a 24-hour window.
- **Robust Configuration:** `HotelTeamConfig` stores recipient emails and alert frequencies per hotel.
- **Data Security:** Alert recipient emails are protected using Active Record Encryption.
- **Throttled Alerting:** The `FinancialObservabilityJob` respects the configured frequency (e.g., daily) and only dispatches the `FinanceAlertMailer` if anomalies are actually detected.
- **Traceability:** Alerts include actor context for override warnings and confirmation tokens for unbalanced folios.

## Known Follow-Ups

- Add more anomaly types as operations identify new risk patterns (e.g., excessive voided charges).
- Surface observability status in the hotel portal dashboard.
