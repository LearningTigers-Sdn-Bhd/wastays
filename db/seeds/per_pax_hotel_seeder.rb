# frozen_string_literal: true

puts "== Seeding Per-Pax Hotel and Bookings =="

# Seeded RNG so repeated runs pick the same guests/room types/statuses/sources -
# reproducible demo data instead of a different shape every time.
RNG = Random.new(20260901) unless defined?(RNG)

PAST_HORIZON_DAYS = 365
FUTURE_HORIZON_DAYS = 60

# 1. Account & Hotel
account = Account.find_by!(slug: "sample-account")

hotel = Hotel.find_or_initialize_by(account: account, name: "Grand Pax Resort")
hotel.city = "Kota Kinabalu"
hotel.country = "Malaysia"
hotel.status = "live"
hotel.address = "101 Pantai Dalit, 89208 Tuaran, Sabah"
hotel.star_rating = 5
hotel.default_currency = "MYR"
hotel.usd_conversion_rate = 4.65
hotel.tourism_tax_enabled = true
hotel.tourism_tax_amount = 10.0
hotel.allow_pax_pricing = true
hotel.pax_pricing_only = true
# Island resort - guests transfer by boat, not car, so front desk needs a boat
# schedule to assign guests to and the kitchen needs boat times to plan meals around
# (see BiboReport / MealPrepReport, both driven entirely by BookingGuest#boat_in_at
# and #boat_out_at).
hotel.allow_boat_information = true
hotel.boat_in_times = %w[08:00 11:00 14:00 16:30]
hotel.boat_out_times = %w[07:30 10:00 13:00 15:30]
hotel.save!
puts "Hotel 'Grand Pax Resort' ready."

# Clean up previous bookings of this hotel to allow clean re-runs. Uses delete_all
# (raw SQL, no callbacks/validations) for folio/billing/financial records rather
# than destroy_all, since most of these associations are dependent:
# :restrict_with_error and would block a normal destroy cascade. Order matters:
# every table below must be cleared before the tables it holds a foreign key to
# (leaf records first, then booking_folios/booking_billing_parties, then bookings).
#
# Bookings that reached "completed" generate an Invoice at checkout (both direct-bill
# and guest-pay - Folios::Lifecycle::IssueClosingDocument always issues one), and
# invoice_revisions are immutable at the DB level (a trigger rejects any UPDATE/DELETE)
# - by design, for audit/compliance reasons. Those bookings can never be destroyed, so
# they're excluded from cleanup entirely and left as-is; seed_pax_booking below skips
# re-creating any confirmation_token that already exists, making a full re-run
# idempotent instead of erroring on them.
all_booking_ids = hotel.bookings.pluck(:id)
invoiced_booking_ids = Booking.joins(booking_folios: :invoice).where(id: all_booking_ids).distinct.pluck(:id)
booking_ids = all_booking_ids - invoiced_booking_ids

# AR (accounts receivable) cleanup - scoped to this hotel's corporate accounts, but
# carefully excluding anything tied to a protected (already-invoiced) booking above,
# since deleting a payment/allocation against an ArInvoice we're keeping would leave
# that invoice's paid_amount/outstanding_amount inconsistent with its payment history.
hotel_corporate_account_ids = HotelCorporateAccount.where(hotel: hotel).pluck(:id)
protected_folio_ids = BookingFolio.where(booking_id: invoiced_booking_ids).pluck(:id)
cleanable_ar_invoice_ids = ArInvoice.where(hotel_corporate_account_id: hotel_corporate_account_ids).where.not(booking_folio_id: protected_folio_ids).pluck(:id)
cleanable_ar_payment_ids = ArPaymentAllocation.where(ar_invoice_id: cleanable_ar_invoice_ids).distinct.pluck(:ar_payment_id)
cleanable_submission_ids = ArPaymentSubmissionAllocation.where(ar_invoice_id: cleanable_ar_invoice_ids).distinct.pluck(:ar_payment_submission_id)

ArPaymentAllocationReversal.where(ar_payment_allocation_id: ArPaymentAllocation.where(ar_payment_id: cleanable_ar_payment_ids).select(:id)).delete_all
ArPaymentAllocation.where(ar_payment_id: cleanable_ar_payment_ids).delete_all
Receipt.where(ar_payment_id: cleanable_ar_payment_ids).delete_all
ArPaymentSubmissionAllocation.where(ar_payment_submission_id: cleanable_submission_ids).delete_all
ArPaymentSubmission.where(id: cleanable_submission_ids).delete_all
ArPayment.where(id: cleanable_ar_payment_ids).delete_all
ArInvoice.where(id: cleanable_ar_invoice_ids).delete_all

folio_ids = BookingFolio.where(booking_id: booking_ids).pluck(:id)
booking_billing_party_ids = BookingBillingParty.where(booking_id: booking_ids).pluck(:id)
deposit_ids = Deposit.where(booking_id: booking_ids).pluck(:id)
folio_transaction_ids = FolioTransaction.where(booking_folio_id: folio_ids).pluck(:id)

BookingAuditLog.where(hotel_id: hotel.id, auditable_type: "Booking", auditable_id: booking_ids).delete_all
FinancialAuditEvent.where(hotel_id: hotel.id, booking_id: booking_ids).delete_all

Receipt.where(folio_transaction_id: folio_transaction_ids).delete_all
Receipt.where(deposit_id: deposit_ids).delete_all
DepositMovement.where(deposit_id: deposit_ids).delete_all
FolioOperationLog.where(booking_id: booking_ids).delete_all
FolioRoutingRule.where(booking_id: booking_ids).delete_all
# Receivable and ArInvoice both map to the ar_invoices table, which references
# invoices - must be cleared before Invoice itself. (booking_ids here already
# excludes invoiced bookings, so this is a no-op safety net, not a real delete.)
Receivable.where(booking_folio_id: folio_ids).delete_all
InvoiceRevision.where(invoice_id: Invoice.where(booking_folio_id: folio_ids).select(:id)).delete_all
Invoice.where(booking_folio_id: folio_ids).delete_all
FolioForecastedCharge.where(booking_folio_id: folio_ids).delete_all
FolioTransaction.where(id: folio_transaction_ids).delete_all
PaymentTransaction.where(booking_id: booking_ids).destroy_all
Deposit.where(id: deposit_ids).delete_all

# Now safe: nothing references booking_folios or booking_billing_parties anymore.
BookingFolio.where(booking_id: booking_ids).delete_all
BookingBillingTerms.where(booking_billing_party_id: booking_billing_party_ids).delete_all
BookingBillingParty.where(booking_id: booking_ids).delete_all
BookingGuest.where(booking_id: booking_ids).delete_all
Booking.where(id: booking_ids).destroy_all
puts "Cleaned up previous bookings for Grand Pax Resort."

# Ensure default GL mappings
Financials::EnsureDefaultGlMaps.call(hotel)

# Property Policy
policy = PropertyPolicy.find_or_initialize_by(hotel: hotel)
policy.check_in_time = "14:00"
policy.check_out_time = "12:00"
policy.cancellation_policy = "Free cancellation up to 48 hours before check-in."
policy.currency = "MYR"
policy.usd_rate = 4.65
policy.save!

# Link Owner Access
owner_role = Role.find_by!(account: account, slug: "hotel_owner")
owner_users = User.where(email: [ "owner@sample.com", "owner@example.com" ])
owner_users.each do |user|
  UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: owner_role)
end

# Create a dedicated per-pax owner user for easy testing/login
pax_user = User.find_or_initialize_by(email: "owner@pax.com")
pax_user.name = "Pax Admin"
pax_user.role = "admin"
pax_user.account = account
pax_user.password = "12345678"
pax_user.password_confirmation = "12345678"
pax_user.save!

UserRole.find_or_create_by!(user: pax_user, role: owner_role)
UserHotelAccess.find_or_create_by!(user: pax_user, hotel: hotel, role: owner_role)
puts "User 'owner@pax.com' ready."

# 2. Room Types & Rooms
room_types_data = [
  {
    name: "Pax Single Studio",
    description: "Cozy single studio designed for solo travelers. Features high-speed Wi-Fi, writing desk, and garden view.",
    max_adults: 1,
    max_children: 0,
    quantity: 5,
    base_price: 100.0,
    room_numbers: [ "101", "102", "103", "104", "105" ]
  },
  {
    name: "Pax Deluxe Twin",
    description: "Elegant twin room with two single beds, private balcony, and ocean breeze.",
    max_adults: 2,
    max_children: 1,
    quantity: 8,
    base_price: 150.0,
    room_numbers: [ "201", "202", "203", "204", "205", "206", "207", "208" ]
  },
  {
    name: "Pax Family Suite",
    description: "Luxurious two-bedroom suite with a living area, dining table, and panoramic sea views.",
    max_adults: 4,
    max_children: 2,
    quantity: 4,
    base_price: 250.0,
    room_numbers: [ "301", "302", "303", "304" ]
  }
]

room_types = {}
room_types_data.each do |rt_data|
  rt = RoomType.find_or_initialize_by(hotel: hotel, name: rt_data[:name])
  rt.description = rt_data[:description]
  rt.max_adults = rt_data[:max_adults]
  rt.max_children = rt_data[:max_children]
  rt.quantity = rt_data[:quantity]
  rt.base_price = rt_data[:base_price]
  rt.room_numbers = rt_data[:room_numbers]
  rt.room_number_mode = "custom"
  rt.save!
  room_types[rt_data[:name]] = rt
  puts "Room Type '#{rt_data[:name]}' created."
end

# 3. Standard Rate Plan
standard_plan = RatePlan.find_or_initialize_by(hotel: hotel, name: "Standard Rate")
standard_plan.sell_mode = "per_person"
standard_plan.currency = "MYR"
standard_plan.single_supplement = 20.0
standard_plan.child_price_multiplier = 0.5
standard_plan.save!

# Delete any existing per pax rate plans
hotel.rate_plans.where(name: [ "Per Pax Flexible Rate", "Per Pax Non-Refundable" ]).destroy_all

puts "Standard Rate Plan ready."

# Link all room types to the standard rate plan
room_types.values.each do |rt|
  RoomTypeRatePlan.find_or_create_by!(room_type: rt, rate_plan: standard_plan)
end

# 3b. Travel agent & direct-bill corporate accounts, so bookings can be attributed to
# an agent (guest still pays, agent gets the credit) or billed direct to a company
# (AR invoice, settled later via ArPayments::RecordPayment / agent payment slips).
def find_or_create_corporate_account(name:, slug:)
  corp_account = Account.find_or_initialize_by(slug: slug)
  corp_account.name = name
  corp_account.account_kind = "corporate"
  corp_account.status = "active"
  corp_account.save!
  corp_account
end

def find_or_create_corporate_user(account:, name:, email:)
  account.users.first || User.create!(name: name, email: email, account: account, role: "corporate", password: "12345678", password_confirmation: "12345678")
end

travel_agent_account = find_or_create_corporate_account(name: "Sunset Travel Partners", slug: "sunset-travel-partners")
travel_agent = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: travel_agent_account)
travel_agent.assign_attributes(
  account_type: "travel_agent",
  relationship_type: "standard",
  credit_limit: nil,
  credit_currency: "MYR",
  payment_terms_days: 14,
  status: "active",
  contact_email: "bookings@sunsettravel.example"
)
travel_agent.save!
find_or_create_corporate_user(account: travel_agent_account, name: "Sunset Travel Bookings", email: travel_agent.contact_email)

corporate_account = find_or_create_corporate_account(name: "Borneo Trading Sdn Bhd", slug: "borneo-trading")
direct_bill_company = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corporate_account)
direct_bill_company.assign_attributes(
  account_type: "company",
  relationship_type: "direct_bill",
  credit_limit: 20_000,
  credit_currency: "MYR",
  payment_terms_days: 30,
  status: "active",
  contact_email: "accounts@borneotrading.example"
)
direct_bill_company.save!
find_or_create_corporate_user(account: corporate_account, name: "Borneo Trading Accounts", email: direct_bill_company.contact_email)
puts "Corporate accounts ready: #{travel_agent_account.name} (travel agent), #{corporate_account.name} (direct-bill)."

# 4. Inventory, Rates & Room Statuses
start_date = Date.current - PAST_HORIZON_DAYS.days
end_date = Date.current + FUTURE_HORIZON_DAYS.days

# Pre-seed business dates as closed/open
(start_date..Date.current).each do |date|
  status = (date == Date.current) ? "open" : "closed"
  hbd = HotelBusinessDate.find_or_initialize_by(hotel: hotel, business_date: date)
  hbd.status = status
  hbd.opened_at = date.to_time + 8.hours
  hbd.closed_at = date.to_time + 23.hours if status == "closed"
  hbd.save!
end

puts "Generating daily RoomInventory and RoomRate records from #{start_date} to #{end_date}..."
room_types.values.each do |rt|
  rates_to_insert = []
  inventories_to_insert = []

  (start_date..end_date).each do |date|
    now = Time.current
    weekend_surcharge = (date.saturday? || date.sunday?) ? 20.0 : 0.0

    # 1. Standard rate
    rates_to_insert << {
      room_type_id: rt.id,
      rate_plan_id: standard_plan.id,
      date: date,
      price: rt.base_price + weekend_surcharge,
      currency: "MYR",
      created_at: now,
      updated_at: now
    }

    # 3. Inventory
    inventories_to_insert << {
      room_type_id: rt.id,
      date: date,
      quantity: rt.quantity,
      status: "open",
      available_room_numbers: rt.room_numbers,
      created_at: now,
      updated_at: now
    }
  end

  # Delete existing daily rates/inventories in the range to avoid duplication
  RoomRate.where(room_type_id: rt.id, date: start_date..end_date).delete_all
  RoomInventory.where(room_type_id: rt.id, date: start_date..end_date).delete_all

  RoomRate.insert_all(rates_to_insert) if rates_to_insert.any?
  RoomInventory.insert_all(inventories_to_insert) if inventories_to_insert.any?
end

# Room statuses
puts "Initializing Room Statuses..."
room_types.values.each do |rt|
  rt.room_numbers.each do |num|
    status = RoomStatus.find_or_initialize_by(hotel: hotel, room_type: rt, room_number: num.to_s)
    status.status = "ready"
    status.last_changed_at = Time.current
    status.notes = "Seeded from room number list"
    status.save!
  end
end

# 5. Seed Guest Profiles
puts "Seeding Guest Profiles..."
guests_data = [
  { name: "John Doe", email: "john.doe@example.com", phone: "+60120000001", gender: "male", country: "Malaysia", document_type: "ic", government_id: "880808-14-8888" },
  { name: "Sarah Smith", email: "sarah.smith@example.com", phone: "+60120000002", gender: "female", country: "United Kingdom", document_type: "passport", government_id: "GB990011A" },
  { name: "Alex Chen", email: "alex.chen@example.com", phone: "+60120000003", gender: "male", country: "Singapore", document_type: "passport", government_id: "SG112233B" },
  { name: "Maria Garcia", email: "maria.garcia@example.com", phone: "+60120000004", gender: "female", country: "Philippines", document_type: "passport", government_id: "PH445566C" },
  { name: "Kenji Tanaka", email: "kenji.tanaka@example.com", phone: "+60120000005", gender: "male", country: "Japan", document_type: "passport", government_id: "JP778899D", date_of_birth: Date.new(1985, 4, 12) },
  { name: "Priya Nair", email: "priya.nair@example.com", phone: "+60120000006", gender: "female", country: "India", document_type: "passport", government_id: "IN334455E", date_of_birth: Date.new(1990, 9, 3) },
  { name: "Liam O'Brien", email: "liam.obrien@example.com", phone: "+60120000007", gender: "male", country: "Ireland", document_type: "passport", government_id: "IE556677F", date_of_birth: Date.new(1978, 11, 21) },
  { name: "Fatimah Zahra", email: "fatimah.zahra@example.com", phone: "+60120000008", gender: "female", country: "Indonesia", document_type: "passport", government_id: "ID998877G", date_of_birth: Date.new(1993, 2, 17) }
]

guests = {}
guests_data.each do |g_data|
  guest = Guest.find_or_initialize_by(email: g_data[:email])
  guest.name = g_data[:name]
  guest.phone = g_data[:phone]
  guest.gender = g_data[:gender]
  guest.country = g_data[:country]
  guest.document_type = g_data[:document_type]
  guest.government_id = g_data[:government_id]
  guest.date_of_birth ||= g_data[:date_of_birth]
  guest.save!
  guests[g_data[:email]] = guest
end
guest_pool = guests.values

# Combines a stay date with an "HH:MM" boat schedule slot into a hotel-timezone Time.
def boat_datetime(hotel, date, time_str)
  hour, minute = time_str.split(":").map(&:to_i)
  date.to_date.in_time_zone(hotel.hotel_time_zone).change(hour: hour, min: minute)
end

# Shifting helper to backdate/future-date bookings perfectly
def shift_booking_dates(booking, days)
  return if days.zero?

  orig_check_in = booking.check_in.to_date
  orig_check_out = booking.check_out.to_date
  orig_stay_dates = (orig_check_in...orig_check_out).to_a

  new_check_in = orig_check_in - days.days
  new_check_out = orig_check_out - days.days
  new_stay_dates = (new_check_in...new_check_out).to_a

  booking.update_columns(
    check_in: booking.check_in - days.days,
    check_out: booking.check_out - days.days,
    created_at: booking.created_at - days.days,
    updated_at: booking.updated_at - days.days,
    checked_in_at: booking.checked_in_at ? booking.checked_in_at - days.days : nil,
    checked_out_at: booking.checked_out_at ? booking.checked_out_at - days.days : nil
  )

  booking.booking_guests.each do |bg|
    updates = {}
    updates[:boat_in_at] = bg.boat_in_at - days.days if bg.boat_in_at
    updates[:boat_out_at] = bg.boat_out_at - days.days if bg.boat_out_at
    bg.update_columns(updates) if updates.any?
  end

  if booking.booking_quote
    booking.booking_quote.update_columns(
      check_in: booking.booking_quote.check_in - days.days,
      check_out: booking.booking_quote.check_out - days.days,
      created_at: booking.booking_quote.created_at - days.days,
      updated_at: booking.booking_quote.updated_at - days.days,
      expires_at: booking.booking_quote.expires_at - days.days
    )
  end

  booking.booking_rooms.each do |br|
    br.update_columns(
      created_at: br.created_at - days.days,
      updated_at: br.updated_at - days.days
    )

    if br.nightly_rate_snapshot.is_a?(Hash)
      shifted_rates = {}
      br.nightly_rate_snapshot.each do |date_str, rate_data|
        new_date_str = (Date.parse(date_str) - days.days).iso8601
        shifted_rates[new_date_str] = rate_data
      end
      br.update_columns(nightly_rate_snapshot: shifted_rates)
    end

    room_type = br.room_type

    # Restore inventory for original dates
    orig_stay_dates.each do |date|
      inventory = room_type.room_inventories.find_by(date: date)
      inventory.update_columns(quantity: inventory.quantity + 1) if inventory
    end

    # Consume inventory for shifted dates
    new_stay_dates.each do |date|
      inventory = room_type.room_inventories.find_by(date: date)
      inventory.update_columns(quantity: [ 0, inventory.quantity - 1 ].max) if inventory
    end
  end

  if booking.booking_folio
    booking.booking_folio.update_columns(
      created_at: booking.booking_folio.created_at - days.days,
      updated_at: booking.booking_folio.updated_at - days.days
    )

    booking.booking_folio.folio_transactions.each do |tx|
      tx.update_columns(
        created_at: tx.created_at - days.days,
        updated_at: tx.updated_at - days.days,
        posted_at: tx.posted_at - days.days,
        posting_date: tx.posting_date - days
      )
    end

    booking.booking_folio.folio_forecasted_charges.each do |fc|
      fc.update_columns(
        stay_date: fc.stay_date - days,
        created_at: fc.created_at - days.days,
        updated_at: fc.updated_at - days.days
      )
    end

    # A direct-bill checkout issues an ArInvoice at "today"'s business date - shift its
    # issued_on/due_on back in step with the booking, same trick as everything else here.
    ar_invoice = booking.booking_folio.ar_invoice
    if ar_invoice
      ar_invoice.update_columns(
        issued_on: ar_invoice.issued_on - days,
        due_on: ar_invoice.due_on - days,
        created_at: ar_invoice.created_at - days.days,
        updated_at: ar_invoice.updated_at - days.days
      )
    end
  end

  booking.payment_transactions.each do |pt|
    pt.update_columns(
      created_at: pt.created_at - days.days,
      updated_at: pt.updated_at - days.days,
      verified_at: pt.verified_at ? pt.verified_at - days.days : nil,
      captured_at: pt.captured_at ? pt.captured_at - days.days : nil
    )
  end

  # Bypassing log updates
  BookingAuditLog.where(auditable_type: "Booking", auditable_id: booking.id).each do |log|
    log.update_columns(
      occurred_at: log.occurred_at - days.days,
      created_at: log.created_at - days.days,
      updated_at: log.updated_at - days.days
    )
  end

  if booking.booking_quote
    BookingAuditLog.where(auditable_type: "BookingQuote", auditable_id: booking.booking_quote.id).each do |log|
      log.update_columns(
        occurred_at: log.occurred_at - days.days,
        created_at: log.created_at - days.days,
        updated_at: log.updated_at - days.days
      )
    end
  end
end

# Helper to manually post nightly charges for a booking's folio before checkout
def post_nightly_charges_for_dates(booking, date_limit)
  folio = booking.booking_folio
  return unless folio

  Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)

  folio.folio_forecasted_charges.forecast.each do |fc|
    next if fc.stay_date > date_limit

    # Insert transaction
    tx = folio.folio_transactions.create!(
      amount: fc.amount,
      transaction_type: "charge",
      category: fc.charge_kind,
      description: fc.description,
      currency: booking.currency,
      posted_at: fc.stay_date.to_time + 22.hours,
      posting_date: fc.stay_date,
      user: nil,
      metadata: {
        posting_source: "night_audit",
        stay_date: fc.stay_date.iso8601,
        booking_id: booking.id,
        charge_kind: fc.charge_kind,
        forecast_identity: fc.identity,
        nightly_charge_key: "nightly:#{booking.id}:#{fc.charge_kind}:#{fc.identity}:#{fc.stay_date.iso8601}"
      }
    )
    # Actualize forecast
    fc.actualize!(transaction: tx)
  end
end

# Random extra folio charges (F&B, parking, laundry, spa) so completed stays look like
# a real resort bill, not just room + tax. Mirrors three_month_active_hotel_seeder.rb.
EXTRA_CHARGE_OPTIONS = [
  { category: "fb", description: "Restaurant - Dinner", min: 35, max: 180, probability: 45 },
  { category: "fb", description: "Room Service - Breakfast", min: 20, max: 60, probability: 30 },
  { category: "parking", description: "Valet Parking", min: 15, max: 30, probability: 20 },
  { category: "other", description: "Laundry Service", min: 25, max: 70, probability: 15 },
  { category: "other", description: "Spa Treatment", min: 80, max: 220, probability: 10 }
].freeze

def post_extra_charges_for_booking(booking, settle: false)
  folio = booking.booking_folio
  return unless folio

  stay_dates = (booking.check_in.to_date...booking.check_out.to_date).to_a
  return if stay_dates.empty?

  extra_total = 0.to_d
  EXTRA_CHARGE_OPTIONS.each do |option|
    next unless RNG.rand(100) < option[:probability]

    date = stay_dates.sample(random: RNG)
    amount = RNG.rand(option[:min]..option[:max]).to_d
    extra_total += amount

    folio.folio_transactions.create!(
      amount: amount,
      transaction_type: "charge",
      category: option[:category],
      description: option[:description],
      currency: booking.currency,
      posted_at: date.to_time + RNG.rand(10..21).hours,
      posting_date: date,
      user: nil,
      metadata: { posting_source: "seed_extra_charge", booking_id: booking.id }
    )
  end

  # Guest-pay checkouts require a zero outstanding balance, so any extra charges
  # need a matching payment before we can transition to "completed". Direct-billed
  # bookings skip this - their outstanding balance rolls into the AR invoice instead.
  if settle && extra_total.positive?
    folio.folio_transactions.create!(
      amount: extra_total,
      transaction_type: "payment",
      category: "cash",
      description: "Cash settlement - extra charges",
      currency: booking.currency,
      posted_at: stay_dates.last.to_time + 21.hours,
      posting_date: stay_dates.last,
      user: nil,
      metadata: { posting_source: "seed_extra_charge_settlement", booking_id: booking.id }
    )
  end
end

def seed_pax_booking(hotel:, room_type:, rate_plan:, guest:, check_in:, check_out:, adults:, children: 0, room_number: nil, status: "confirmed", payment_status: "captured", confirmation_token: nil, shift_days: 0, source: "internal", hotel_corporate_account: nil, direct_bill: false)
  # Bookings that already reached "completed" hold an immutable invoice (see cleanup
  # comment above) and were left untouched by the cleanup pass - skip re-creating them
  # so re-running this seeder is idempotent instead of hitting a confirmation_token
  # uniqueness error.
  if confirmation_token.present? && (existing = Booking.find_by(confirmation_token: confirmation_token))
    puts "  Booking #{confirmation_token} already exists (id=#{existing.id}), skipping."
    return existing
  end

  # We perform the creation for future/current dates so it passes availability/closing checks, then we shift it.
  effective_check_in = check_in + shift_days.days
  effective_check_out = check_out + shift_days.days

  # Create Quote
  quote_service = BookingEngine::CreateQuote.new(
    hotel_id: hotel.id,
    allocations: [ { room_type_id: room_type.id, quantity: 1 } ],
    check_in: effective_check_in,
    check_out: effective_check_out,
    adults: adults,
    children: children,
    rate_plan_id: rate_plan.id,
    guest_name: guest.name,
    guest_email: guest.email,
    guest_phone: guest.phone,
    hotel_corporate_account_id: hotel_corporate_account&.id
  )
  quote_res = quote_service.call
  unless quote_res.success?
    puts "  [Skip] Failed to create quote for #{guest.name} (#{room_type.name}, #{check_in}): #{quote_res.message}"
    return nil
  end

  quote = quote_res.quote

  # Confirm booking
  payment_details = {
    guest_name: guest.name,
    guest_email: guest.email,
    guest_phone: guest.phone,
    government_id: guest.government_id,
    gender: guest.gender,
    country: guest.country,
    document_type: guest.document_type
  }
  confirm_service = BookingEngine::ConfirmBooking.new(quote_token: quote.token, payment_details: payment_details)
  confirm_res = confirm_service.call
  unless confirm_res.success?
    puts "  [Skip] Failed to confirm booking for #{guest.name} (#{room_type.name}, #{check_in}): #{confirm_res.message}"
    return nil
  end

  booking = confirm_res.booking
  booking.update_columns(source: source, hotel_corporate_account_id: hotel_corporate_account&.id)

  # Boat-in/boat-out times (island resort transfers) - feeds both the BIBO log and
  # the kitchen's meal-prep counts (breakfast/lunch/dinner derived purely from what
  # hour the boat lands/leaves). Applies to every booking regardless of status, since
  # guests book their transfer slot up front - past, current, and upcoming stays alike.
  primary_guest = booking.booking_guests.first
  if primary_guest
    boat_in_time = hotel.boat_in_times.sample(random: RNG)
    boat_out_time = hotel.boat_out_times.sample(random: RNG)
    primary_guest.update_columns(
      boat_in_at: boat_datetime(hotel, effective_check_in, boat_in_time),
      boat_out_at: boat_datetime(hotel, effective_check_out, boat_out_time)
    )
  end

  # Check-in requires every room to have a number assigned - auto-pick one if the
  # caller didn't specify it (the volume-generated bookings below don't).
  if room_number.blank? && status.in?(%w[checked_in completed])
    room_number = Bookings::AvailableRoomNumbers.new(hotel: hotel, room_type: room_type, check_in: effective_check_in, check_out: effective_check_out).call.first
  end

  # Assign room number
  if room_number.present?
    booking.booking_rooms.first.update!(room_number: room_number)
  end

  # Direct-billed bookings are settled later via an AR invoice, not a guest payment.
  unless direct_bill
    PaymentTransaction.create!(
      booking: booking,
      gateway: "razorpay",
      external_reference: "pay_#{booking.confirmation_token || SecureRandom.hex(4)}",
      gateway_order_id: "order_#{booking.confirmation_token || SecureRandom.hex(4)}",
      status: "captured",
      payment_method: "card",
      amount_subunits: (booking.total_amount.to_f * 100).to_i,
      currency: booking.currency,
      event_source: "client_callback",
      verified_at: Time.current,
      captured_at: Time.current,
      metadata: { confirmation_token: booking.confirmation_token }
    )
  end

  # Initialize folio
  Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: nil, options: { override_night_audit: true }, lock: false)

  # 1. Post nightly (+ extra) charges if checking in or completing
  if status == "checked_in"
    # Post charge only for yesterday (the check-in night)
    post_nightly_charges_for_dates(booking, effective_check_in)
  elsif status == "completed"
    # Post all stay charges plus a random mix of F&B/parking/spa
    post_nightly_charges_for_dates(booking, effective_check_out)
    post_extra_charges_for_booking(booking, settle: !direct_bill)
  end

  # 2. Transition to checked_in / completed if necessary
  if status == "checked_in" || status == "completed"
    tx = Bookings::TransitionStatus.new(
      booking: booking,
      status: "checked_in",
      timestamp: effective_check_in.to_time + 15.hours,
      options: { override_night_audit: true, reason: "Demo seed check-in" }
    ).call
    puts "  [Error] Failed to check in: #{tx.error}" unless tx.success?
  end

  if status == "completed"
    checkout_options = { override_night_audit: true, reason: "Demo seed check-out" }
    checkout_options[:direct_bill_folio_ids] = [ booking.booking_folio.id ] if direct_bill

    tx = Bookings::TransitionStatus.new(
      booking: booking,
      status: "completed",
      timestamp: effective_check_out.to_time + 11.hours,
      options: checkout_options
    ).call
    puts "  [Error] Failed to check out: #{tx.error}" unless tx.success?

    # RoomStatus tracks the room's real-world condition, not per-date state - reset it
    # immediately so this historical checkout doesn't permanently block the room for
    # every later booking we seed against it.
    if room_number.present?
      RoomStatus.where(hotel: hotel, room_type: room_type, room_number: room_number).update_all(status: "ready", last_changed_at: Time.current)
    end
  end

  if status == "cancelled"
    tx = Bookings::TransitionStatus.new(
      booking: booking,
      status: "cancelled",
      options: { reason: "Guest requested cancellation" }
    ).call
    puts "  [Error] Failed to cancel: #{tx.error}" unless tx.success?
  end

  # Now shift the booking dates back by shift_days
  shift_booking_dates(booking, shift_days)

  # Explicit overrides
  booking.update_columns(
    confirmation_token: confirmation_token,
    payment_status: payment_status
  ) if confirmation_token.present?

  margin_rate = hotel.effective_margin_rate(room_type).to_f
  margin_amount = (booking.total_amount * (margin_rate / 100.0)).round(2)
  booking.update_columns(
    margin_rate: margin_rate,
    margin_amount: margin_amount,
    net_amount: booking.total_amount - margin_amount
  )

  puts "  Booking #{booking.confirmation_token} created successfully! Total amount: #{booking.total_amount} #{booking.currency}"
  booking
end

# Scenario 1: Past Booking - Solo Guest (Single Supplement)
# Checked in 12 days ago, checked out 9 days ago.
# Room: Pax Single Studio
# Pax: 1 adult
# Nights: 3
# Rate Plan: Per Pax Standard Rate
seed_pax_booking(
  hotel: hotel,
  room_type: room_types["Pax Single Studio"],
  rate_plan: standard_plan,
  guest: guests["sarah.smith@example.com"],
  check_in: Date.current - 12.days,
  check_out: Date.current - 9.days,
  adults: 1,
  room_number: "101",
  status: "completed",
  confirmation_token: "WS-PAX-PST-001",
  shift_days: 15
)

# Scenario 2: Past Booking - Multi-generational Family (Child Multiplier)
# Checked in 6 days ago, checked out 4 days ago.
# Room: Pax Family Suite
# Pax: 2 adults, 2 children
# Nights: 2
# Rate Plan: Standard Rate
seed_pax_booking(
  hotel: hotel,
  room_type: room_types["Pax Family Suite"],
  rate_plan: standard_plan,
  guest: guests["john.doe@example.com"],
  check_in: Date.current - 6.days,
  check_out: Date.current - 4.days,
  adults: 2,
  children: 2,
  room_number: "301",
  status: "completed",
  confirmation_token: "WS-PAX-PST-002",
  shift_days: 8
)

# Scenario 3: Current Booking - Couple (Active - In house)
# Checked in yesterday, checking out tomorrow.
# Room: Pax Deluxe Twin
# Pax: 2 adults
# Nights: 2
# Rate Plan: Standard Rate
seed_pax_booking(
  hotel: hotel,
  room_type: room_types["Pax Deluxe Twin"],
  rate_plan: standard_plan,
  guest: guests["alex.chen@example.com"],
  check_in: Date.current - 1.day,
  check_out: Date.current + 1.day,
  adults: 2,
  room_number: "201",
  status: "checked_in",
  confirmation_token: "WS-PAX-ACT-003",
  shift_days: 2
)

# Scenario 4: Current Booking - Solo traveler (Active - In house)
# Checked in today, checking out in 3 days.
# Room: Pax Deluxe Twin
# Pax: 1 adult
# Nights: 3
# Rate Plan: Standard Rate
seed_pax_booking(
  hotel: hotel,
  room_type: room_types["Pax Deluxe Twin"],
  rate_plan: standard_plan,
  guest: guests["maria.garcia@example.com"],
  check_in: Date.current,
  check_out: Date.current + 3.days,
  adults: 1,
  room_number: "202",
  status: "checked_in",
  confirmation_token: "WS-PAX-ACT-004",
  shift_days: 0
)

# Scenario 5: Future Booking - Large Family (Upcoming)
# Checking in in 7 days, checking out in 10 days.
# Room: Pax Family Suite
# Pax: 3 adults, 2 children
# Nights: 3
# Rate Plan: Standard Rate
seed_pax_booking(
  hotel: hotel,
  room_type: room_types["Pax Family Suite"],
  rate_plan: standard_plan,
  guest: guests["john.doe@example.com"],
  check_in: Date.current + 7.days,
  check_out: Date.current + 10.days,
  adults: 3,
  children: 2,
  status: "confirmed",
  confirmation_token: "WS-PAX-FUT-005",
  shift_days: 0
)

# Scenario 6: Future Booking - Solo Guest (Upcoming)
# Checking in in 14 days, checking out in 15 days.
# Room: Pax Single Studio
# Pax: 1 adult
# Nights: 1
# Rate Plan: Standard Rate
seed_pax_booking(
  hotel: hotel,
  room_type: room_types["Pax Single Studio"],
  rate_plan: standard_plan,
  guest: guests["sarah.smith@example.com"],
  check_in: Date.current + 14.days,
  check_out: Date.current + 15.days,
  adults: 1,
  status: "confirmed",
  confirmation_token: "WS-PAX-FUT-006",
  shift_days: 0
)

# 7. Volume: a year of booking history plus a couple of months ahead, mixing direct
# guests (varied sources), a travel agent, and a direct-bill corporate account, so the
# hotel looks like it's actually been operating rather than freshly switched on.
puts "Generating a year of booking history (this takes a while)..."

GUEST_SOURCES = %w[walk_in phone whatsapp internal agoda booking_com traveloka airbnb].freeze
room_type_pool = room_types.values.flat_map { |rt| [ rt ] * rt.quantity }

def pick_party(room_type)
  adults = RNG.rand(1..room_type.max_adults)
  children = room_type.max_children.positive? && RNG.rand(100) < 30 ? RNG.rand(1..room_type.max_children) : 0
  [ adults, children ]
end

def pick_nights
  roll = RNG.rand(100)
  return 1 if roll < 60
  return 2 if roll < 90

  3
end

generated = { completed: 0, cancelled: 0, confirmed: 0, corporate: 0, agent: 0, skipped: 0 }
loop_index = 0
day = Date.current - PAST_HORIZON_DAYS.days

while day <= Date.current + FUTURE_HORIZON_DAYS.days
  loop_index += 1

  # Skip most days so occupancy looks plausible rather than fully booked every night.
  unless RNG.rand(100) < 55
    day += RNG.rand(1..3).days
    next
  end

  room_type = room_type_pool.sample(random: RNG)
  adults, children = pick_party(room_type)
  nights = pick_nights
  check_in = day
  check_out = day + nights.days
  guest = guest_pool.sample(random: RNG)
  token = format("WS-PAX-GEN-%04d", loop_index)

  bucket = RNG.rand(100)
  hotel_corporate_account = nil
  direct_bill = false
  source = GUEST_SOURCES.sample(random: RNG)

  if bucket < 12
    hotel_corporate_account = direct_bill_company
    direct_bill = true
    source = "corporate"
    generated[:corporate] += 1
  elsif bucket < 22
    hotel_corporate_account = travel_agent
    source = "corporate"
    generated[:agent] += 1
  end

  in_past = check_out <= Date.current
  in_future = check_in > Date.current

  status =
    if in_past
      RNG.rand(100) < 6 ? "cancelled" : "completed"
    elsif in_future
      RNG.rand(100) < 5 ? "cancelled" : "confirmed"
    else
      # Straddles today - treat as checked in (rare, only when the sampled window happens to include today).
      "checked_in"
    end

  shift_days = check_in < Date.current ? (Date.current - check_in).to_i : 0
  payment_status = direct_bill ? "pending" : "captured"

  booking = seed_pax_booking(
    hotel: hotel,
    room_type: room_type,
    rate_plan: standard_plan,
    guest: guest,
    check_in: check_in,
    check_out: check_out,
    adults: adults,
    children: children,
    status: status,
    payment_status: payment_status,
    confirmation_token: token,
    shift_days: shift_days,
    source: source,
    hotel_corporate_account: hotel_corporate_account,
    direct_bill: direct_bill
  )

  generated[status.to_sym] = (generated[status.to_sym] || 0) + 1 if booking
  generated[:skipped] += 1 if booking.nil?

  day += RNG.rand(1..3).days
end

puts "Booking history generated: #{generated.inspect}"

# 8. Settle the direct-bill company's AR invoices: some fully paid, some partially
# paid, the rest left open so overdue aging shows up too. Guarded by
# `ar_payment_allocations.none?` so re-running the seeder never double-pays an
# already-settled (and now-immutable) invoice.
acting_user = pax_user
open_invoices = direct_bill_company.ar_invoices.select { |invoice| invoice.ar_payment_allocations.none? && invoice.outstanding_amount.to_d.positive? }

open_invoices.each_with_index do |invoice, index|
  bucket = index % 3
  next if bucket == 2 # leave roughly a third open/unpaid so aging buckets have data

  amount = bucket.zero? ? invoice.outstanding_amount.to_d : (invoice.outstanding_amount.to_d * 0.5).round(2)
  received_at = [ invoice.issued_on + RNG.rand(2..10).days, Date.current ].min

  result = ArPayments::RecordPayment.call(
    hotel: hotel,
    hotel_corporate_account: direct_bill_company,
    user: acting_user,
    amount: amount,
    currency: invoice.currency,
    reference_number: "BT-PMT-#{invoice.invoice_number}",
    received_at: received_at,
    payment_method: %w[bank_transfer cheque].sample(random: RNG),
    allocations: { invoice.id => amount },
    metadata: { seeded: true }
  )
  puts "  [Error] Failed to record AR payment for invoice #{invoice.invoice_number}: #{result.error}" unless result.success?
end
puts "AR invoices settled for #{corporate_account.name}: #{open_invoices.size} processed."

# 9. Agent-submitted payment slips for the corporate portal demo (one pending, one
# rejected), so the AR payment-submissions review screen has real data to show.
sample_slip_path = Rails.root.join("spec/fixtures/files/sample_image.jpg")
outstanding_invoices = direct_bill_company.ar_invoices.select { |invoice| invoice.outstanding_amount.to_d.positive? }

if outstanding_invoices.any? && File.exist?(sample_slip_path) && direct_bill_company.ar_payment_submissions.none?
  agent_user = corporate_account.users.first
  slip_prefix = "BT-SLIP-#{Date.current.strftime('%Y%m')}"

  pending_invoice = outstanding_invoices.first
  pending_amount = [ 500.0, pending_invoice.outstanding_amount.to_d ].min
  pending_submission = direct_bill_company.ar_payment_submissions.new(
    hotel: hotel, submitted_by: agent_user, amount: pending_amount, currency: "MYR",
    reference_number: "#{slip_prefix}A", received_at: Date.current - 2.days, payment_method: "bank_transfer",
    notes: "Settlement for last month's stays"
  )
  pending_submission.ar_payment_submission_allocations.build(ar_invoice: pending_invoice, amount: pending_amount)
  pending_submission.slip.attach(io: File.open(sample_slip_path), filename: "slip.jpg", content_type: "image/jpeg")
  pending_submission.save!

  rejected_invoice = outstanding_invoices.second || pending_invoice
  rejected_amount = [ 250.0, rejected_invoice.outstanding_amount.to_d ].min
  rejected_submission = direct_bill_company.ar_payment_submissions.new(
    hotel: hotel, submitted_by: agent_user, amount: rejected_amount, currency: "MYR",
    reference_number: "#{slip_prefix}B", received_at: Date.current - 6.days, payment_method: "bank_transfer",
    status: "rejected", rejection_reason: "Reference number does not match any outstanding invoice.",
    reviewed_by: pax_user, reviewed_at: Date.current - 5.days
  )
  rejected_submission.ar_payment_submission_allocations.build(ar_invoice: rejected_invoice, amount: rejected_amount)
  rejected_submission.slip.attach(io: File.open(sample_slip_path), filename: "slip.jpg", content_type: "image/jpeg")
  rejected_submission.save!

  puts "Seeded 1 pending and 1 rejected agent payment submission for #{corporate_account.name}."
else
  puts "[Skip] Agent payment submissions (no outstanding invoice, missing fixture, or already seeded)."
end

puts "Seeding complete!"
