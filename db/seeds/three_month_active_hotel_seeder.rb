# frozen_string_literal: true

#
# Seeds a fictional hotel with realistic operating history from its opening
# day (1 Jan 2026) through today (past/completed stays, current in-house
# guests, future confirmed bookings) covering both guest-pay and
# corporate-billed business — private companies, government, travel
# agents, and an airline — so the folio, AR invoice, AR payment, and
# Agent Summary screens have real-looking data to review. Safe to re-run:
# destroys and rebuilds this hotel's bookings and AR history each time.
#
# Usage: bin/rails runner db/seeds/three_month_active_hotel_seeder.rb

puts "== Seeding Active Hotel Since Opening Day (Corporate AR Demo) =="

# Avoid the overhead of rendering/opening a browser tab for every booking
# confirmation email while seeding dozens of bookings.
ActionMailer::Base.delivery_method = :test

RNG = Random.new(20260714)

TODAY = Date.current
PAST_HORIZON = Date.new(2026, 1, 1)
FUTURE_HORIZON = TODAY + 30.days

# 1. Account & Hotel
account = Account.find_by!(slug: "sample-account")

hotel = Hotel.find_or_initialize_by(account: account, name: "Tanjung Harbour Hotel")
hotel.city = "Kota Kinabalu"
hotel.country = "Malaysia"
hotel.status = "live"
hotel.address = "88 Jalan Pantai, 88000 Kota Kinabalu, Sabah"
hotel.star_rating = 4
hotel.default_currency = "MYR"
hotel.usd_conversion_rate = 4.65
hotel.sell_mode = "per_room"
hotel.tourism_tax_enabled = true
hotel.tourism_tax_amount = 10.0
hotel.sst_enabled = true
hotel.save!
puts "Hotel 'Tanjung Harbour Hotel' ready (id=#{hotel.id})."

# Clean up previous run's data for a clean re-seed
booking_ids = hotel.bookings.pluck(:id)
folio_ids = BookingFolio.where(booking_id: booking_ids).pluck(:id)
hotel_corporate_account_ids = HotelCorporateAccount.where(hotel: hotel).pluck(:id)

ArPaymentAllocationReversal.where(ar_payment_allocation_id: ArPaymentAllocation.where(ar_payment_id: ArPayment.where(hotel_corporate_account_id: hotel_corporate_account_ids).select(:id)).select(:id)).delete_all
ArPaymentAllocation.where(ar_payment_id: ArPayment.where(hotel_corporate_account_id: hotel_corporate_account_ids).select(:id)).delete_all
ArPaymentSubmissionAllocation.where(ar_payment_submission_id: ArPaymentSubmission.where(hotel_corporate_account_id: hotel_corporate_account_ids).select(:id)).delete_all
ArPaymentSubmission.where(hotel_corporate_account_id: hotel_corporate_account_ids).delete_all
ArPayment.where(hotel_corporate_account_id: hotel_corporate_account_ids).delete_all
ArInvoice.where(hotel_corporate_account_id: hotel_corporate_account_ids).delete_all

# BookingBillingParty is deliberately protected from cascading deletes (restrict_with_error),
# so unwind its dependents/references explicitly before destroying bookings.
booking_billing_party_ids = BookingBillingParty.where(booking_id: booking_ids).pluck(:id)
BookingBillingTerms.where(booking_billing_party_id: booking_billing_party_ids).delete_all
BookingFolio.where(booking_id: booking_ids).update_all(booking_billing_party_id: nil)
BookingBillingParty.where(booking_id: booking_ids).delete_all

BookingAuditLog.where(hotel_id: hotel.id).delete_all
FinancialAuditEvent.where(hotel_id: hotel.id).delete_all
FolioForecastedCharge.where(booking_folio_id: folio_ids).delete_all
FolioTransaction.where(booking_folio_id: folio_ids).delete_all
PaymentTransaction.where(booking_id: booking_ids).destroy_all
Deposit.where(booking_id: booking_ids).delete_all

# Delete folios directly (rather than via Booking's cascade) — Booking declares both a
# has_many :booking_folios and a has_one :booking_folio dependent: :destroy over the same
# rows, and the second pass fails trying to re-destroy an already-destroyed record.
BookingFolio.where(booking_id: booking_ids).delete_all
BookingGuest.where(booking_id: booking_ids).delete_all
hotel.bookings.destroy_all
puts "Cleaned up previous bookings and AR history for this hotel."

Financials::EnsureDefaultGlMaps.call(hotel)
Financials::EnsureDefaultTransactionCodes.call(hotel)
room_revenue_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
room_revenue_code.update!(is_taxable: true)
room_revenue_code.transaction_code_taxes.find_or_create_by!(primary_tax_key: "sst_tax")
puts "SST 8% tax rule attached to Room Revenue."

# Property Policy
policy = PropertyPolicy.find_or_initialize_by(hotel: hotel)
policy.check_in_time = "14:00"
policy.check_out_time = "12:00"
policy.cancellation_policy = "Free cancellation up to 48 hours before check-in."
policy.currency = "MYR"
policy.usd_rate = 4.65
policy.save!

# Staff access
owner_role = Role.find_by!(account: account, slug: "hotel_owner")
User.where(email: [ "owner@sample.com", "owner@example.com" ]).each do |user|
  UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: owner_role)
end

front_desk_user = User.find_or_initialize_by(email: "frontdesk@harbour.com")
front_desk_user.name = "Nurul Aina"
front_desk_user.role = "admin"
front_desk_user.account = account
front_desk_user.password = "12345678"
front_desk_user.password_confirmation = "12345678"
front_desk_user.save!
UserRole.find_or_create_by!(user: front_desk_user, role: owner_role)
UserHotelAccess.find_or_create_by!(user: front_desk_user, hotel: hotel, role: owner_role)
puts "Staff user 'frontdesk@harbour.com' ready."

# 2. Room Types
room_types_data = [
  { name: "Superior Room", description: "Comfortable 24sqm room with one queen bed and city view.", max_adults: 2, max_children: 1, quantity: 10, base_price: 180.0, room_numbers: (101..110).map(&:to_s) },
  { name: "Deluxe Room", description: "32sqm room with king bed, work desk, and harbour glimpse.", max_adults: 2, max_children: 2, quantity: 8, base_price: 240.0, room_numbers: (201..208).map(&:to_s) },
  { name: "Family Suite", description: "Two-room suite with separate living area, ideal for families.", max_adults: 4, max_children: 2, quantity: 5, base_price: 380.0, room_numbers: (301..305).map(&:to_s) },
  { name: "Executive Suite", description: "Top-floor suite with lounge access and panoramic sea view.", max_adults: 3, max_children: 1, quantity: 4, base_price: 520.0, room_numbers: (401..404).map(&:to_s) }
]

room_types = {}
room_types_data.each do |rt_data|
  rt = Rooms::SaveSeedRoomType.call!(
    hotel:,
    attributes: rt_data.merge(room_number_mode: "custom")
  )
  room_types[rt_data[:name]] = rt
  puts "Room Type '#{rt_data[:name]}' ready (#{rt_data[:quantity]} units)."
end

# 3. Rate Plans — a standard rack rate, and a discounted corporate rate
standard_plan = RatePlan.find_or_initialize_by(hotel: hotel, name: "Standard Rate")
standard_plan.kind = "standard"
standard_plan.sell_mode = "per_room"
standard_plan.currency = "MYR"
standard_plan.save!

corporate_plan = RatePlan.find_or_initialize_by(hotel: hotel, name: "Corporate Negotiated Rate")
corporate_plan.sell_mode = "per_room"
corporate_plan.currency = "MYR"
corporate_plan.save!

room_types.values.each do |rt|
  RoomTypeRatePlan.find_or_create_by!(room_type: rt, rate_plan: standard_plan)
  RoomTypeRatePlan.find_or_create_by!(room_type: rt, rate_plan: corporate_plan)
end
puts "Rate plans 'Standard Rate' and 'Corporate Negotiated Rate' ready."

# 4. Business dates, inventory & rates across the full window
(PAST_HORIZON..TODAY).each do |date|
  status = (date == TODAY) ? "open" : "closed"
  hbd = HotelBusinessDate.find_or_initialize_by(hotel: hotel, business_date: date)
  hbd.status = status
  hbd.opened_at = date.to_time + 8.hours
  hbd.closed_at = date.to_time + 23.hours if status == "closed"
  hbd.save!
end

puts "Generating RoomInventory and RoomRate from #{PAST_HORIZON} to #{FUTURE_HORIZON}..."
room_types.values.each do |rt|
  rates_to_insert = []
  inventories_to_insert = []
  now = Time.current

  (PAST_HORIZON..FUTURE_HORIZON).each do |date|
    rates_to_insert << { room_type_id: rt.id, rate_plan_id: standard_plan.id, date: date, price: rt.base_price, currency: "MYR", created_at: now, updated_at: now }
    rates_to_insert << { room_type_id: rt.id, rate_plan_id: corporate_plan.id, date: date, price: (rt.base_price * 0.85).round(2), currency: "MYR", created_at: now, updated_at: now }
    inventories_to_insert << { room_type_id: rt.id, date: date, quantity: rt.quantity, status: "open", available_room_numbers: rt.room_numbers, created_at: now, updated_at: now }
  end

  RoomRate.where(room_type_id: rt.id, date: PAST_HORIZON..FUTURE_HORIZON).delete_all
  RoomInventory.where(room_type_id: rt.id, date: PAST_HORIZON..FUTURE_HORIZON).delete_all
  RoomRate.insert_all(rates_to_insert) if rates_to_insert.any?
  RoomInventory.insert_all(inventories_to_insert) if inventories_to_insert.any?
end

room_types.values.each do |rt|
  rt.room_numbers.each do |num|
    status = RoomStatus.find_or_initialize_by(hotel: hotel, room_type: rt, room_number: num.to_s)
    status.status = "ready"
    status.last_changed_at = Time.current
    status.notes = "Seeded"
    status.save!
  end
end

# 5. Guest profiles (walk-in / OTA / direct guests)
guests_data = [
  { name: "John Doe", email: "john.doe@example.com", phone: "+60120000001", gender: "male", country: "Malaysia", document_type: "ic", government_id: "880808-14-8888" },
  { name: "Sarah Smith", email: "sarah.smith@example.com", phone: "+60120000002", gender: "female", country: "United Kingdom", document_type: "passport", government_id: "GB990011A", date_of_birth: Date.new(1990, 3, 14) },
  { name: "Alex Chen", email: "alex.chen@example.com", phone: "+60120000003", gender: "male", country: "Singapore", document_type: "passport", government_id: "SG112233B", date_of_birth: Date.new(1985, 7, 22) },
  { name: "Maria Garcia", email: "maria.garcia@example.com", phone: "+60120000004", gender: "female", country: "Philippines", document_type: "passport", government_id: "PH445566C", date_of_birth: Date.new(1992, 11, 5) },
  { name: "Ahmad Zulkifli", email: "ahmad.zulkifli@example.com", phone: "+60120000005", gender: "male", country: "Malaysia", document_type: "ic", government_id: "900101-12-5566" },
  { name: "Tan Mei Ling", email: "tan.meiling@example.com", phone: "+60120000006", gender: "female", country: "Malaysia", document_type: "ic", government_id: "870303-12-3344" },
  { name: "David Wilson", email: "david.wilson@example.com", phone: "+60120000007", gender: "male", country: "Australia", document_type: "passport", government_id: "AU778899C", date_of_birth: Date.new(1978, 5, 30) },
  { name: "Yuki Tanaka", email: "yuki.tanaka@example.com", phone: "+60120000008", gender: "female", country: "Japan", document_type: "passport", government_id: "JP334455D", date_of_birth: Date.new(1995, 2, 18) },
  { name: "Siti Nurhaliza", email: "siti.nurhaliza@example.com", phone: "+60120000009", gender: "female", country: "Malaysia", document_type: "ic", government_id: "910909-12-7788" },
  { name: "Robert Lee", email: "robert.lee@example.com", phone: "+60120000010", gender: "male", country: "Hong Kong", document_type: "passport", government_id: "HK556677E", date_of_birth: Date.new(1982, 9, 9) },
  { name: "Nurul Huda", email: "nurul.huda@example.com", phone: "+60120000011", gender: "female", country: "Malaysia", document_type: "ic", government_id: "930505-12-9900" },
  { name: "Michael Brown", email: "michael.brown@example.com", phone: "+60120000012", gender: "male", country: "United States", document_type: "passport", government_id: "US112244F", date_of_birth: Date.new(1975, 12, 1) },
  { name: "Lim Wei Jian", email: "lim.weijian@example.com", phone: "+60120000013", gender: "male", country: "Malaysia", document_type: "ic", government_id: "890707-12-1122" },
  { name: "Fatimah Zahra", email: "fatimah.zahra@example.com", phone: "+60120000014", gender: "female", country: "Indonesia", document_type: "passport", government_id: "ID998877G", date_of_birth: Date.new(1988, 4, 25) }
]

guests = {}
guests_data.each do |g|
  guest = Guest.find_or_initialize_by(email: g[:email])
  guest.assign_attributes(name: g[:name], phone: g[:phone], gender: g[:gender], country: g[:country], document_type: g[:document_type], government_id: g[:government_id], date_of_birth: g[:date_of_birth], created_by_hotel_id: hotel.id)
  guest.save!
  guests[g[:email]] = guest
end
puts "#{guests.size} guest profiles ready."

# 6. Corporate accounts — private companies, government, and agents/airline
def find_or_create_corporate_account(name:, slug:)
  account = Account.find_or_initialize_by(slug: slug)
  account.name = name
  account.account_kind = "corporate"
  account.status = "active"
  account.save!
  account
end

# Each corporate account gets exactly one login user (User#account_id must be
# unique for corporate-role users), so the corporate portal is reachable.
def find_or_create_corporate_user(account:, name:, email:)
  account.users.first || User.create!(
    name: name,
    email: email,
    account: account,
    role: "corporate",
    password: "12345678",
    password_confirmation: "12345678"
  )
end

corporates = {}

corp_account = find_or_create_corporate_account(name: "Borneo Techlink Sdn Bhd", slug: "borneo-techlink")
hca = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corp_account)
hca.assign_attributes(account_type: "company", relationship_type: "direct_bill", direct_bill_enabled: true, credit_limit: 25_000, credit_currency: "MYR", payment_terms_days: 30, status: "active", contact_email: "ap@borneotechlink.example")
hca.save!
find_or_create_corporate_user(account: corp_account, name: "Techlink Accounts", email: hca.contact_email)
corporates[:company_direct_bill] = hca

corp_account = find_or_create_corporate_account(name: "Pantai Resort Supplies Sdn Bhd", slug: "pantai-resort-supplies")
hca = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corp_account)
hca.assign_attributes(account_type: "company", relationship_type: "standard", direct_bill_enabled: false, credit_currency: "MYR", status: "active", contact_email: "finance@pantairesortsupplies.example")
hca.save!
find_or_create_corporate_user(account: corp_account, name: "Pantai Resort Supplies Accounts", email: hca.contact_email)
corporates[:company_standard] = hca

corp_account = find_or_create_corporate_account(name: "Kota Kinabalu City Council", slug: "kk-city-council")
hca = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corp_account)
hca.assign_attributes(account_type: "government", relationship_type: "direct_bill", direct_bill_enabled: true, credit_limit: 60_000, credit_currency: "MYR", payment_terms_days: 45, status: "active", contact_email: "treasury@kkcouncil.example")
hca.save!
find_or_create_corporate_user(account: corp_account, name: "KK City Council Treasury", email: hca.contact_email)
corporates[:government] = hca

corp_account = find_or_create_corporate_account(name: "Borneo Wanderlust Travel Agency", slug: "borneo-wanderlust")
hca = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corp_account)
hca.assign_attributes(account_type: "travel_agent", relationship_type: "direct_bill", direct_bill_enabled: true, credit_limit: 18_000, credit_currency: "MYR", payment_terms_days: 14, status: "active", contact_email: "accounts@borneowanderlust.example")
hca.save!
find_or_create_corporate_user(account: corp_account, name: "Wanderlust Accounts", email: hca.contact_email)
corporates[:travel_agent] = hca

corp_account = find_or_create_corporate_account(name: "Sabah Sunrise Tours & Travel", slug: "sabah-sunrise-tours")
hca = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corp_account)
hca.assign_attributes(account_type: "travel_agent", relationship_type: "direct_bill", direct_bill_enabled: true, credit_limit: 12_000, credit_currency: "MYR", payment_terms_days: 21, status: "active", contact_email: "finance@sabahsunrisetours.example")
hca.save!
find_or_create_corporate_user(account: corp_account, name: "Sabah Sunrise Accounts", email: hca.contact_email)
corporates[:travel_agent_2] = hca

corp_account = find_or_create_corporate_account(name: "SkyBorneo Airlines Crew Desk", slug: "skyborneo-crew")
hca = HotelCorporateAccount.find_or_initialize_by(hotel: hotel, corporate_account: corp_account)
hca.assign_attributes(account_type: "airline", relationship_type: "direct_bill", direct_bill_enabled: true, credit_limit: 35_000, credit_currency: "MYR", payment_terms_days: 30, status: "active", contact_email: "crewaccommodation@skyborneo.example")
hca.save!
find_or_create_corporate_user(account: corp_account, name: "SkyBorneo Crew Desk Accounts", email: hca.contact_email)
corporates[:airline] = hca

puts "#{corporates.size} corporate accounts ready: #{corporates.values.map { |c| c.corporate_account.name }.join(', ')}"
puts "#{corporates.size} corporate logins ready (password: 12345678): #{corporates.values.map { |c| c.contact_email }.join(', ')}"

# 7. Helpers (adapted from db/seeds/per_pax_hotel_seeder.rb)

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

  booking.booking_rooms.each do |br|
    br.update_columns(created_at: br.created_at - days.days, updated_at: br.updated_at - days.days)

    if br.nightly_rate_snapshot.is_a?(Hash)
      shifted = {}
      br.nightly_rate_snapshot.each { |date_str, data| shifted[(Date.parse(date_str) - days.days).iso8601] = data }
      br.update_columns(nightly_rate_snapshot: shifted)
    end

    room_type = br.room_type
    orig_stay_dates.each do |date|
      inv = room_type.room_inventories.find_by(date: date)
      inv.update_columns(quantity: inv.quantity + 1) if inv
    end
    new_stay_dates.each do |date|
      inv = room_type.room_inventories.find_by(date: date)
      inv.update_columns(quantity: [ 0, inv.quantity - 1 ].max) if inv
    end
  end

  if booking.booking_folio
    booking.booking_folio.update_columns(created_at: booking.booking_folio.created_at - days.days, updated_at: booking.booking_folio.updated_at - days.days)

    booking.booking_folio.folio_transactions.each do |tx|
      tx.update_columns(created_at: tx.created_at - days.days, updated_at: tx.updated_at - days.days, posted_at: tx.posted_at - days.days, posting_date: tx.posting_date - days)
    end

    booking.booking_folio.folio_forecasted_charges.each do |fc|
      fc.update_columns(stay_date: fc.stay_date - days, created_at: fc.created_at - days.days, updated_at: fc.updated_at - days.days)
    end

    if booking.booking_folio.ar_invoice
      inv = booking.booking_folio.ar_invoice
      inv.update_columns(issued_on: inv.issued_on - days, due_on: inv.due_on - days, created_at: inv.created_at - days.days, updated_at: inv.updated_at - days.days)
    end
  end

  booking.payment_transactions.each do |pt|
    pt.update_columns(created_at: pt.created_at - days.days, updated_at: pt.updated_at - days.days, verified_at: pt.verified_at ? pt.verified_at - days.days : nil, captured_at: pt.captured_at ? pt.captured_at - days.days : nil)
  end

  BookingAuditLog.where(auditable_type: "Booking", auditable_id: booking.id).each do |log|
    log.update_columns(occurred_at: log.occurred_at - days.days, created_at: log.created_at - days.days, updated_at: log.updated_at - days.days)
  end
end

def post_nightly_charges_for_dates(booking, date_limit)
  folio = booking.booking_folio
  return unless folio

  Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)

  folio.folio_forecasted_charges.forecast.each do |fc|
    next if fc.stay_date > date_limit

    tx = folio.folio_transactions.create!(
      amount: fc.amount,
      currency: folio.currency,
      transaction_type: "charge",
      category: fc.charge_kind,
      description: fc.description,
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
    fc.actualize!(transaction: tx)
  end
end

# Incidental extra charges (F&B, parking, laundry, spa) that a real hotel folio would
# accumulate alongside room and tax charges, so "Other Charges" isn't always zero.
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

  total_extra = 0.to_d

  EXTRA_CHARGE_OPTIONS.each do |option|
    next if RNG.rand(100) >= option[:probability]

    date = stay_dates.sample(random: RNG)
    amount = RNG.rand(option[:min]..option[:max]).to_d

    folio.folio_transactions.create!(
      amount: amount,
      currency: folio.currency,
      transaction_type: "charge",
      category: option[:category],
      description: option[:description],
      posted_at: date.to_time + RNG.rand(10..21).hours,
      posting_date: date,
      user: nil,
      metadata: { posting_source: "seed_extra_charge" }
    )
    total_extra += amount
  end

  return if total_extra.zero? || !settle

  # Guest-pay checkouts require a zero outstanding balance, so settle the extra
  # charges in cash before the checkout transition runs. Direct-billed bookings
  # skip this — their outstanding balance rolls into the AR invoice instead.
  folio.folio_transactions.create!(
    amount: total_extra,
    currency: folio.currency,
    transaction_type: "payment",
    category: "cash",
    description: "Extra charges settlement",
    posted_at: stay_dates.last.to_time + 21.hours,
    posting_date: stay_dates.last,
    user: nil,
    metadata: { posting_source: "seed_extra_charge_settlement" }
  )
end

# seed_booking drives Bookings::CreateManualBooking end-to-end: creates,
# posts nightly charges, transitions status, then (for past-dated
# scenarios) shifts everything back in time so it lands on the intended
# historical date.
def seed_booking(hotel:, user:, room_type:, rate_plan:, guest:, check_in:, check_out:, adults:, children: 0, status:, source:, hotel_corporate_account: nil, payment_method: "card", direct_bill: false)
  shift_days = check_in < Date.current ? (Date.current - check_in).to_i : 0
  effective_check_in = check_in + shift_days.days
  effective_check_out = check_out + shift_days.days

  # Check-in/checkout requires a real room number assigned, so always pick one that's
  # actually free for these dates rather than leaving the booking unassigned.
  room_number = Bookings::AvailableRoomNumbers.new(hotel: hotel, room_type: room_type, check_in: effective_check_in, check_out: effective_check_out).call.first
  if room_number.blank?
    puts "  [Skip] No available #{room_type.name} for #{guest.name} on #{check_in}."
    return nil
  end

  params = {
    room_type_id: room_type.id,
    rate_plan_id: rate_plan.id,
    room_number: room_number,
    check_in: effective_check_in,
    check_out: effective_check_out,
    adults: adults,
    children: children,
    guest_name: guest.name,
    guest_email: guest.email,
    guest_phone: guest.phone,
    guest_country: guest.country,
    guest_gender: guest.gender,
    guest_document_type: guest.document_type,
    guest_government_id: guest.government_id,
    source: source,
    hotel_corporate_account_id: hotel_corporate_account&.id
  }

  if direct_bill
    params[:record_payment] = false
  else
    params[:record_payment] = true
    params[:payment_method] = payment_method
  end

  result = Bookings::CreateManualBooking.new(hotel: hotel, params: params, user: user).call
  unless result.success?
    puts "  [Error] Failed to create booking (#{guest.name}, #{room_type.name}, #{check_in}): #{result.errors&.join(', ')}"
    return nil
  end

  booking = result.booking

  if status == "checked_in"
    post_nightly_charges_for_dates(booking, effective_check_in)
    post_extra_charges_for_booking(booking)
  elsif status == "completed"
    post_nightly_charges_for_dates(booking, effective_check_out)
    post_extra_charges_for_booking(booking, settle: !direct_bill)
  end

  if status.in?(%w[checked_in completed])
    tx = Bookings::TransitionStatus.new(booking: booking, status: "checked_in", timestamp: effective_check_in.to_time + 15.hours, user: user, options: { override_night_audit: true, reason: "Demo seed check-in" }).call
    puts "  [Error] Failed to check in: #{tx.error}" unless tx.success?
  end

  if status == "completed"
    checkout_options = { override_night_audit: true, reason: "Demo seed check-out" }
    checkout_options[:direct_bill_folio_ids] = [ booking.booking_folio.id ] if direct_bill
    tx = Bookings::TransitionStatus.new(booking: booking, status: "completed", timestamp: effective_check_out.to_time + 11.hours, user: user, options: checkout_options).call
    puts "  [Error] Failed to check out: #{tx.error}" unless tx.success?

    # RoomStatus tracks the room's real-world condition, not per-date state — reset it
    # immediately so this historical checkout doesn't permanently block the room for
    # every later booking we seed against it.
    RoomStatus.where(hotel: hotel, room_type: room_type, room_number: room_number).update_all(status: "ready", last_changed_at: Time.current)
  end

  if status == "cancelled"
    tx = Bookings::TransitionStatus.new(booking: booking, status: "cancelled", user: user, options: { reason: "Guest requested cancellation" }).call
    puts "  [Error] Failed to cancel: #{tx.error}" unless tx.success?
  end

  shift_booking_dates(booking, shift_days)
  booking
end

# 8. Generate bookings across the 3-month window
guest_pool = guests.values
guest_payment_methods = %w[cash card bank_transfer]
guest_sources = %w[walk_in agoda whatsapp internal]
corporate_accounts_pool = [ corporates[:company_direct_bill], corporates[:company_standard], corporates[:government], corporates[:travel_agent], corporates[:travel_agent_2], corporates[:airline] ]
room_type_pool = room_types.values

created_bookings = { past: 0, current: 0, future: 0, cancelled: 0, corporate: 0, guest_pay: 0 }

def pick_stay(rng, room_type)
  adults = [ 1, 2, [ 2, room_type.max_adults ].min ].sample(random: rng)
  children = rng.rand(10) < 3 ? [ 1, room_type.max_children ].min : 0
  los = rng.rand(1..4)
  [ adults, children, los ]
end

puts "\nSeeding past (completed) bookings..."
day = PAST_HORIZON
while day < TODAY - 4.days
  # Roughly every 1-2 days, book 2-3 stays starting around this date
  bookings_today = RNG.rand(2..3)
  bookings_today.times do
    room_type = room_type_pool.sample(random: RNG)
    adults, children, los = pick_stay(RNG, room_type)
    check_in = day
    check_out = check_in + los.days
    next if check_out > TODAY - 3.days

    is_corporate = RNG.rand(100) < 35
    is_cancelled = !is_corporate && RNG.rand(100) < 4

    if is_corporate
      hca = corporate_accounts_pool.sample(random: RNG)
      direct_bill = hca.direct_bill_enabled?
      guest = guest_pool.sample(random: RNG)
      booking = seed_booking(
        hotel: hotel, user: front_desk_user, room_type: room_type, rate_plan: corporate_plan,
        guest: guest, check_in: check_in, check_out: check_out, adults: adults, children: children,
        status: "completed", source: "corporate", hotel_corporate_account: hca, direct_bill: direct_bill
      )
      created_bookings[:corporate] += 1 if booking
    else
      guest = guest_pool.sample(random: RNG)
      status = is_cancelled ? "cancelled" : "completed"
      booking = seed_booking(
        hotel: hotel, user: front_desk_user, room_type: room_type, rate_plan: standard_plan,
        guest: guest, check_in: check_in, check_out: check_out, adults: adults, children: children,
        status: status, source: guest_sources.sample(random: RNG), payment_method: guest_payment_methods.sample(random: RNG)
      )
      created_bookings[:cancelled] += 1 if booking && is_cancelled
      created_bookings[:guest_pay] += 1 if booking && !is_cancelled
    end
    created_bookings[:past] += 1 if booking
  end
  day += RNG.rand(1..2).days
end

# Simulate housekeeping catching up: every past checkout leaves its room "dirty" until
# cleaned, and by "today" all of them should have been turned around and be ready again.
RoomStatus.where(hotel: hotel).update_all(status: "ready", last_changed_at: Time.current)
puts "Reset room statuses to 'ready' after past bookings (housekeeping turnover)."

puts "Seeding current (in-house) bookings..."
current_scenarios = [
  { room: "Deluxe Room", ci: -2, co: 1, adults: 2, children: 0, corporate: nil },
  { room: "Superior Room", ci: -1, co: 2, adults: 1, children: 0, corporate: nil },
  { room: "Family Suite", ci: -1, co: 3, adults: 3, children: 1, corporate: :company_direct_bill },
  { room: "Executive Suite", ci: 0, co: 4, adults: 2, children: 0, corporate: :airline },
  { room: "Superior Room", ci: 0, co: 1, adults: 2, children: 0, corporate: nil },
  { room: "Deluxe Room", ci: -1, co: 2, adults: 2, children: 1, corporate: :travel_agent },
  { room: "Superior Room", ci: -2, co: 2, adults: 2, children: 0, corporate: :travel_agent_2 }
]
current_scenarios.each do |sc|
  room_type = room_types[sc[:room]]
  guest = guest_pool.sample(random: RNG)
  hca = sc[:corporate] ? corporates[sc[:corporate]] : nil
  booking = seed_booking(
    hotel: hotel, user: front_desk_user, room_type: room_type, rate_plan: hca ? corporate_plan : standard_plan,
    guest: guest, check_in: TODAY + sc[:ci].days, check_out: TODAY + sc[:co].days, adults: sc[:adults], children: sc[:children],
    status: "checked_in", source: hca ? "corporate" : "walk_in", hotel_corporate_account: hca,
    payment_method: guest_payment_methods.sample(random: RNG), direct_bill: hca&.direct_bill_enabled? || false
  )
  next unless booking

  created_bookings[:current] += 1
  hca ? created_bookings[:corporate] += 1 : created_bookings[:guest_pay] += 1
end

puts "Seeding future (confirmed) bookings..."
day = TODAY + 3.days
while day < FUTURE_HORIZON - 4.days
  bookings_today = RNG.rand(1..2)
  bookings_today.times do
    room_type = room_type_pool.sample(random: RNG)
    adults, children, los = pick_stay(RNG, room_type)
    check_in = day
    check_out = check_in + los.days
    next if check_out > FUTURE_HORIZON

    is_corporate = RNG.rand(100) < 30
    guest = guest_pool.sample(random: RNG)

    if is_corporate
      hca = corporate_accounts_pool.sample(random: RNG)
      booking = seed_booking(
        hotel: hotel, user: front_desk_user, room_type: room_type, rate_plan: corporate_plan,
        guest: guest, check_in: check_in, check_out: check_out, adults: adults, children: children,
        status: "confirmed", source: "corporate", hotel_corporate_account: hca, direct_bill: hca.direct_bill_enabled?
      )
      created_bookings[:corporate] += 1 if booking
    else
      booking = seed_booking(
        hotel: hotel, user: front_desk_user, room_type: room_type, rate_plan: standard_plan,
        guest: guest, check_in: check_in, check_out: check_out, adults: adults, children: children,
        status: "confirmed", source: guest_sources.sample(random: RNG), payment_method: guest_payment_methods.sample(random: RNG)
      )
      created_bookings[:guest_pay] += 1 if booking
    end
    created_bookings[:future] += 1 if booking
  end
  day += RNG.rand(1..2).days
end

puts "Bookings created: #{created_bookings}"

# 9. Simulate AR payment history against the direct-bill invoices generated at checkout
puts "\nSimulating AR payment history..."
invoices = ArInvoice.where(hotel_corporate_account_id: corporates.values.map(&:id)).order(:issued_on)

settled = partial = unpaid = 0
invoices.each_with_index do |invoice, index|
  invoice.reload
  next if invoice.outstanding_amount.zero?

  hca = invoice.hotel_corporate_account
  bucket = index % 3

  case bucket
  when 0
    # Fully paid, a few days after issue
    result = ArPayments::RecordPayment.call(
      hotel: hotel, hotel_corporate_account: hca, user: front_desk_user,
      amount: invoice.amount, currency: invoice.currency,
      reference_number: "PMT-#{invoice.id}-FULL", received_at: [ invoice.issued_on + RNG.rand(2..10).days, TODAY ].min,
      payment_method: %w[bank_transfer cheque].sample(random: RNG),
      allocations: { invoice.id => invoice.amount }
    )
    settled += 1 if result.success?
    puts "  [Error] #{result.error}" unless result.success?
  when 1
    # Partially paid
    partial_amount = (invoice.amount * 0.5).round(2)
    result = ArPayments::RecordPayment.call(
      hotel: hotel, hotel_corporate_account: hca, user: front_desk_user,
      amount: partial_amount, currency: invoice.currency,
      reference_number: "PMT-#{invoice.id}-PART", received_at: [ invoice.issued_on + RNG.rand(3..12).days, TODAY ].min,
      payment_method: %w[bank_transfer cheque].sample(random: RNG),
      allocations: { invoice.id => partial_amount }
    )
    partial += 1 if result.success?
    puts "  [Error] #{result.error}" unless result.success?
  else
    # Left unpaid (will show as overdue once due_on has passed)
    unpaid += 1
  end
end
puts "AR invoices: #{invoices.size} total (#{settled} fully paid, #{partial} partially paid, #{unpaid} unpaid)."

# 10. Agent-submitted payment slips for the corporate portal demo (one pending,
# one rejected, per travel agent) so the Agent Summary / submissions review
# screens have more than a single account to show.
travel_agent_hcas = [ corporates[:travel_agent], corporates[:travel_agent_2] ].compact
sample_slip_path = Rails.root.join("spec/fixtures/files/sample_image.jpg")

travel_agent_hcas.each_with_index do |travel_agent_hca, idx|
  travel_agent_outstanding_invoices = travel_agent_hca.ar_invoices.select { |inv| inv.outstanding_amount.to_d.positive? }

  unless travel_agent_outstanding_invoices.any? && File.exist?(sample_slip_path)
    puts "  [Skip] No outstanding invoice available for #{travel_agent_hca.corporate_account.name} agent payment submission demo."
    next
  end

  agent_user = travel_agent_hca.corporate_account.users.first
  slip_prefix = "AGENT-SLIP-#{TODAY.strftime('%Y%m')}-#{idx + 1}"

  pending_invoice = travel_agent_outstanding_invoices.first
  pending_amount = [ 850.0, pending_invoice.outstanding_amount.to_d ].min
  pending_submission = travel_agent_hca.ar_payment_submissions.new(
    hotel: hotel, submitted_by: agent_user, amount: pending_amount, currency: "MYR",
    reference_number: "#{slip_prefix}A", received_at: TODAY - 2.days, payment_method: "bank_transfer",
    notes: "Settlement for last week's bookings"
  )
  pending_submission.ar_payment_submission_allocations.build(ar_invoice: pending_invoice, amount: pending_amount)
  pending_submission.slip.attach(io: File.open(sample_slip_path), filename: "slip.jpg", content_type: "image/jpeg")
  pending_submission.save!

  rejected_invoice = travel_agent_outstanding_invoices.second || pending_invoice
  rejected_amount = [ 320.0, rejected_invoice.outstanding_amount.to_d ].min
  rejected_submission = travel_agent_hca.ar_payment_submissions.new(
    hotel: hotel, submitted_by: agent_user, amount: rejected_amount, currency: "MYR",
    reference_number: "#{slip_prefix}B", received_at: TODAY - 6.days, payment_method: "bank_transfer",
    status: "rejected", rejection_reason: "Reference number does not match any outstanding invoice.",
    reviewed_by: front_desk_user, reviewed_at: TODAY - 5.days
  )
  rejected_submission.ar_payment_submission_allocations.build(ar_invoice: rejected_invoice, amount: rejected_amount)
  rejected_submission.slip.attach(io: File.open(sample_slip_path), filename: "slip.jpg", content_type: "image/jpeg")
  rejected_submission.save!

  puts "Seeded 1 pending and 1 rejected agent payment submission for #{travel_agent_hca.corporate_account.name}."
end

puts "\n== Seeding complete =="
puts "Login as frontdesk@harbour.com / 12345678 to explore Tanjung Harbour Hotel."
