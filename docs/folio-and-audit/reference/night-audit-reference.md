# Night Audit — PMS Reference

## What Is Night Audit?

Night audit is a **batch process** that runs once per day, usually at midnight or during low-occupancy hours. It closes the current business day and opens the next. It is the heartbeat of the PMS — what keeps folios accurate day by day.

---

## Folio Timeline Overview

A folio lives across the entire stay, with charges posting at specific trigger points:

```
CHECK-IN          DAY 1→2         DAY 2→3         DAY 3→4        CHECK-OUT
    |                |               |               |               |
 Folio opens    Night Audit     Night Audit     Night Audit     Folio closes
 Deposit        posts Room+Tax  posts Room+Tax  posts Room+Tax  Balance settled
 applied        + incidentals   + incidentals   + incidentals   Invoice issued
```

---

## Night Audit Sequence

### Step 1: Pre-Audit Checks
- All in-house folios balanced?
- Any open transactions not posted?
- No pending check-ins/check-outs?
- POS systems closed and synced?

### Step 2: Room & Tax Posting
For every occupied room:
- Post room charge (based on rate plan)
- Calculate tax (by jurisdiction rules)
- Append to folio as line items

### Step 3: Package Posting
- Post included package items (breakfast, parking)
- Attach to relevant folio lines

### Step 4: No-Show Processing
- Identify reservations that didn't arrive
- Apply no-show charge
- Release room back to inventory

### Step 5: Day Roll (Business Date Change)
- Close current business date
- Open the next `HotelBusinessDate` in `open` state
- All new transactions now post to new date
- Record immutable audit events for the completed audit, closed date, and opened date

**Force Roll Escape Hatch:**
If critical blockers cannot be resolved immediately, an authorized user (with `override_financial_date_lock`) can initiate a "Force Roll." This action:
- Moves the current date to `force_closed`.
- Marks the night audit as completed but with `force_closed: true`.
- Atomically opens the next `HotelBusinessDate`.
- Records a `night_audit_force_rolled` event in the financial ledger.

Implementation guarantees:
- The close/open transition is atomic with the successful audit completion transaction.
- Blocked or failed audits leave the next business date unopened unless force-rolled.
- If the next business date already exists and is `open`, it is reused.
- If the next business date already exists in a locked state (`audit_running`, `audit_blocked`, `closed`, or `force_closed`), the audit fails safely instead of overwriting that state.
- Business-date rows are locked before their state is trusted, and duplicate-row races are retried through the existing unique hotel/date constraint.

### Step 6: Reconciliation & Reports
- Revenue report (rooms, F&B, tax)
- Occupancy report
- Departure list for next day
- Folio balance report (any negative or unusual balances flagged)

---

## Folio Timeline — Day by Day Example

**Scenario:** Guest checks in May 18, checks out May 21. 3 nights at $100/night, 10% tax. Fully prepaid ($330).

### Check-In (May 18)
```
Folio opened
├── Advance deposit applied:   -$330   (prepaid full stay)
└── Balance:                   -$330   (credit)
```

### Night Audit — End of May 18
```
System date closes: May 18 → opens May 19
├── Room charge (May 18):      +$100
├── Tax (10%):                 +$10
└── Folio balance:             -$220
```

### Night Audit — End of May 19
```
System date closes: May 19 → opens May 20
├── Room charge (May 19):      +$100
├── Tax (10%):                 +$10
└── Folio balance:             -$110
```

### Night Audit — End of May 20
```
System date closes: May 20 → opens May 21
├── Room charge (May 20):      +$100
├── Tax (10%):                 +$10
└── Folio balance:             $0.00  ✓
```

### Check-Out (May 21)
```
No additional room charge (checkout day not billed)
Balance: $0.00 → Folio closed, invoice issued
```

> **Rule:** Checkout day is never charged. Only nights slept are billed.

---

## Rate Plan & Tax Rules Engine

Night audit doesn't post a flat number — it evaluates the **rate plan** each night:

```
Rate Plan: RACK_SUMMER
├── Base rate:          $100
├── Weekend surcharge:  +$20 (Fri/Sat)
├── Tax rule:           10% room tax + 5% tourism levy
└── Package:            Breakfast included → post $15 F&B credit
```

Each night audit run:
1. Looks up the rate plan for that room/reservation
2. Checks if it's a weekday / weekend / holiday
3. Applies the correct rate
4. Calculates each tax component separately (required for reporting)
5. Posts each as individual line items

---

## What Night Audit Posts to the Folio

Each cycle creates **multiple line items**, not just one:

| Date   | Description              | Charge   | Credit   |
|--------|--------------------------|----------|----------|
| May 18 | Room Charge - RACK       | $100.00  |          |
| May 18 | State Room Tax (10%)     | $10.00   |          |
| May 18 | Tourism Levy (5%)        | $5.00    |          |
| May 18 | Breakfast Package        |          | $15.00   |
| May 19 | Room Charge - RACK       | $100.00  |          |
| May 19 | State Room Tax (10%)     | $10.00   |          |
| ...    | ...                      | ...      | ...      |

This granularity matters for:
- **Revenue reporting** — room revenue, tax, F&B separated
- **Tax remittance** — each tax type tracked independently
- **Folio disputes** — guest can see exactly what was charged and when

---

## Edge Cases

### Early Check-Out
```
Guest booked 5 nights, leaves after 3.
├── Night audit only ran 3 times → 3 nights charged ✓
├── If fully prepaid → refund 2 nights
├── If non-refundable rate → post cancellation fee, no refund
└── Folio closed on day 3, not day 5
```

### Late Check-Out
```
Guest checks out at 3pm (cutoff was 11am)
├── Late check-out fee posted manually by front desk
├── Night audit does NOT run again for their room
└── Fee added as one-time charge, folio closed same day
```

### No-Show
```
Guest never arrives
├── Night audit flags reservation at end of day
├── No-show charge posted (usually 1 night + tax)
├── Room released back to inventory
└── A folio may still be created to hold the charge
```

### Rate Correction After Audit
```
Wrong rate posted last night → manager needs to:
├── Post a negative adjustment (rebate) for the wrong amount
├── Post correct charge for the right amount
└── Both appear on folio with audit trail
```

> **Rule:** Never delete a posted charge. Always use adjustments or rebates. The audit trail must remain intact.

---

## Key Rules Summary

| Rule | Why It Matters |
|------|----------------|
| Never delete a posted charge | Audit trail — always use adjustments/rebates |
| Each tax component is a separate line | Tax reporting requires breakdown |
| Business date ≠ system clock | Night audit controls the date, not the server time |
| Successful audit opens next date | New postings must land on the next operational day |
| Failed or blocked audit does not advance date | Staff must resolve blockers before the hotel rolls forward |
| Checkout day is not charged | Industry standard — only nights slept are billed |
| Audit runs even if hotel is empty | The business day must roll regardless |
| Rate plan is re-evaluated each night | Weekend/holiday rates may differ mid-stay |
