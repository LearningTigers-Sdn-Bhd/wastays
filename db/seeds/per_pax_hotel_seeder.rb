# frozen_string_literal: true

puts "== Seeding Per-Pax Hotel and Bookings =="

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
hotel.save!
puts "Hotel 'Grand Pax Resort' ready."

# Clean up previous bookings of this hotel to allow clean re-runs
booking_ids = hotel.bookings.pluck(:id)
folio_ids = BookingFolio.where(booking_id: booking_ids).pluck(:id)
BookingAuditLog.where(hotel_id: hotel.id).delete_all
FinancialAuditEvent.where(hotel_id: hotel.id).delete_all
FolioForecastedCharge.where(booking_folio_id: folio_ids).delete_all
FolioTransaction.where(booking_folio_id: folio_ids).delete_all
PaymentTransaction.where(booking_id: booking_ids).destroy_all
Deposit.where(booking_id: booking_ids).delete_all
hotel.bookings.destroy_all
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

# 4. Inventory, Rates & Room Statuses
start_date = Date.current - 30.days
end_date = Date.current + 60.days

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
  { name: "Maria Garcia", email: "maria.garcia@example.com", phone: "+60120000004", gender: "female", country: "Philippines", document_type: "passport", government_id: "PH445566C" }
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
  guest.save!
  guests[g_data[:email]] = guest
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

def seed_pax_booking(hotel:, room_type:, rate_plan:, guest:, check_in:, check_out:, adults:, children: 0, room_number: nil, status: "confirmed", payment_status: "captured", confirmation_token: nil, shift_days: 0)
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
    guest_phone: guest.phone
  )
  quote_res = quote_service.call
  unless quote_res.success?
    puts "  [Error] Failed to create quote: #{quote_res.message}"
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
    puts "  [Error] Failed to confirm booking: #{confirm_res.message}"
    return nil
  end

  booking = confirm_res.booking

  # Assign room number
  if room_number.present?
    booking.booking_rooms.first.update!(room_number: room_number)
  end

  # Create a payment transaction so it syncs onto the folio
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

  # Initialize folio
  Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: nil, options: { override_night_audit: true }, lock: false)

  # 1. Post nightly charges if checking in or completing
  if status == "checked_in"
    # Post charge only for yesterday (the check-in night)
    post_nightly_charges_for_dates(booking, effective_check_in)
  elsif status == "completed"
    # Post all stay charges
    post_nightly_charges_for_dates(booking, effective_check_out)
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
    tx = Bookings::TransitionStatus.new(
      booking: booking,
      status: "completed",
      timestamp: effective_check_out.to_time + 11.hours,
      options: { override_night_audit: true, reason: "Demo seed check-out" }
    ).call
    puts "  [Error] Failed to check out: #{tx.error}" unless tx.success?
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

puts "Seeding complete!"
