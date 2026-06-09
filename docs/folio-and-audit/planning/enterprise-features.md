# Enterprise Vision: The Future of Wastays

The features outlined in this planning document represent the strategic transition of Wastays from a boutique Property Management System (PMS) into a globally scalable, enterprise-grade Property Management System.

---

## Theme 1: Billing Sophistication & Routing
**Goal**: Support complex commercial arrangements and multi-party billing.

- **Folio Splitting & Dynamic Transfers**: 
  - Ability to split a single reservation into multiple folios (e.g., Folio A for Guest room charges, Folio B for Company-paid meals).
  - Automated routing rules that move specific categories (e.g., "Mini-bar") to secondary folios without manual intervention.
- **Group Master Folios**: 
  - Centralized "Master Records" for large groups, weddings, or corporate events, allowing for bulk billing and group-wide settlement.

---

## Theme 2: Corporate & B2B Commercials
**Goal**: Deepen relationships with travel agents and corporate partners.

- **City Ledger / Accounts Receivable (AR)**: 
  - Direct invoicing for B2B partners, enabling "Credit Billing" where guests stay now and companies pay later.
  - Accounts Receivable (AR) Aging Reports (30/60/90 days) to manage collections and credit risk.
- **Enterprise Accounting Exports**: 
  - Certified data exports for major ERPs (Oracle, SAP, Xero) to bridge the gap between hospitality and finance.

---

## Theme 3: Group Inventory & Advanced Logistics
**Goal**: Manage high-volume inventory movements with precision.

- **Group Blocks & Cut-off Automation**: 
  - Reserving blocks of rooms for events with "wash" rules that automatically release unreserved rooms back to general inventory on a specific date.
- **Housekeeping & Maintenance Integration**: 
  - Deep cleaning cycles and preventive maintenance work orders that directly impact room availability and revenue potential.

---

## Theme 4: Security, Compliance & Isolation
**Goal**: Maintain the highest standards of data integrity and financial safety.

- **PCI-Compliant Tokenization (Card-on-File)**: 
  - Implementation of secure vaulting (e.g., Stripe/Braintree) to allow "no-show" charging and incidental pre-authorizations without storing sensitive data.
- **PostgreSQL Row Level Security (RLS)**: 
  - Database policy-level isolation to ensure that multi-property enterprise users can never access data across distinct legal entities.
