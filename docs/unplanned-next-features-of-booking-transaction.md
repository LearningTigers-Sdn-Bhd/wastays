# Unplanned Next Features: Professional/Enterprise Grade PMS

This document outlines the identified gaps and next-level features required to elevate the current system from a solid independent PMS to a professional, enterprise-grade Property Management System.

## 1. Advanced Folio Management (Billing & Routing)
- **Folio Splitting**: Ability to split a single reservation's bill into multiple folios (e.g., Folio A for Room & Tax, Folio B for incidentals).
- **Charge Routing**: Automatic routing rules based on transaction category (e.g., all "Food & Beverage" charges automatically move to a specific folio).
- **Folio Transfers**: Ability to move charges between different rooms or folios manually.

## 2. Group Bookings & Room Blocks
- **Group Master Records**: A parent entity for multi-room reservations.
- **Master Folios**: A central folio to handle billing for an entire group.
- **Inventory Blocking**: Reserving a block of rooms without assigning specific guest names immediately.
- **Cut-off Dates**: Automated release of unpicked-up rooms from a group block back into general inventory.

## 3. Accounts Receivable (AR) / City Ledger
- **B2B Billing**: Direct invoicing for Corporate Clients and Travel Agents.
- **Aging Reports**: Tracking outstanding payments across 30/60/90 day periods.
- **Bulk Payments**: Applying a single check or wire transfer against multiple reservations/invoices.

## 4. PCI-Compliant Payment Tokenization
- **Card on File**: Integration with a vaulting service (Stripe, etc.) to store secure tokens instead of raw card data.
- **Pre-authorizations**: Holding funds for incidentals upon check-in.
- **Automated Penalty Processing**: Charging no-show or late-cancellation fees directly to the vaulted card.

## 5. Enhanced Multi-Tenant Isolation
- **Row Level Security (RLS)**: Implementing PostgreSQL RLS to ensure hardware-level data isolation between different hotel properties.

## 6. Housekeeping & Maintenance Integration
- **Deep Cleaning Cycles**: Managing non-daily cleaning schedules.
- **Maintenance Work Orders**: Tracking room repairs and automatically setting rooms to "Out of Service" during maintenance.
