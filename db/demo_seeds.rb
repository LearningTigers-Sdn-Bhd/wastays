# frozen_string_literal: true

module DemoSeedLog
  module_function

  def section(title)
    puts
    puts "== #{title} #{'=' * [ 0, 72 - title.length ].max}"
  end

  def step(message)
    puts "-> #{message}"
  end

  def ok(message)
    puts "   OK: #{message}"
  end
end

module DemoSeeds
  module_function

  PASSWORD = "12345678"
  DATE_RANGE_START = Date.current - 45.days
  DATE_RANGE_END = Date.current + 75.days

  PERMISSIONS = [
    { name: "Manage Account", slug: "manage_account" },
    { name: "Manage Hotel Profile", slug: "manage_hotel_profile" },
    { name: "Manage Room Types", slug: "manage_room_types" },
    { name: "Manage Rates", slug: "manage_rates" },
    { name: "Manage Inventory", slug: "manage_inventory" },
    { name: "View Bookings", slug: "view_bookings" },
    { name: "Manage Bookings", slug: "manage_bookings" },
    { name: "View Guest Phone", slug: "view_guest_phone" },
    { name: "Manage Guest Arrival", slug: "manage_guest_arrival" },
    { name: "View Audit Logs", slug: "view_audit_logs" },
    { name: "Export Audit Logs", slug: "export_audit_logs" },
    { name: "Manage Night Audit", slug: "manage_night_audit" },
    { name: "Manage Users", slug: "manage_users" },
    { name: "View Reports", slug: "view_reports" },
    { name: "View Payouts", slug: "view_payouts" }
  ].freeze

  ROLE_TEMPLATES = [
    { name: "Hotel Owner", slug: "hotel_owner", permissions: %w[manage_account manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users manage_night_audit view_reports view_payouts] },
    { name: "General Manager", slug: "general_manager", permissions: %w[manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users manage_night_audit view_reports view_payouts] },
    { name: "Front Desk", slug: "front_desk", permissions: %w[view_bookings manage_bookings manage_guest_arrival manage_night_audit] },
    { name: "Reservation Staff", slug: "reservation_staff", permissions: %w[view_bookings manage_bookings view_guest_phone] }
  ].freeze

  CANCELLATION_TEMPLATES = [
    { name: "Flexible", body: "Full refund if cancelled at least 24 hours before check-in time. No refund if cancelled within 24 hours." },
    { name: "Moderate", body: "Full refund if cancelled at least 5 days before check-in time. 50% refund if cancelled between 2 and 5 days. No refund within 48 hours." },
    { name: "Strict", body: "No refund for cancellations." }
  ].freeze

  DEMO_ACCOUNT_SLUGS = %w[
    demo-platform
    demo-luma-stays
    demo-coastline-collection
    demo-aurora-signature
    demo-riverstone-labs
  ].freeze

  DEMO_API_KEY_NAMES = [
    "Demo Global API Key",
    "Demo Cedar API Key",
    "Demo Coastline API Key",
    "Demo Aurora API Key"
  ].freeze

  def run
    raise "Demo seeds may only run in demo environment." unless Rails.env.demo?

    DemoSeedLog.section("Seeding demo environment")

    ensure_permissions_and_templates
    reset_demo_scope!
    configure_platform_defaults

    contexts = seed_accounts_hotels_and_users
    backfill_room_statuses
    seed_quotes(contexts)
    seed_bookings_and_guest_journeys(contexts)
    seed_requests(contexts)
    seed_payouts(contexts)
    seed_admin_surfaces(contexts)

    DemoSeedLog.section("Demo credentials")
    puts "superadmin@wastays.com / #{PASSWORD}"
    puts "s@s.com / #{PASSWORD}"
    puts "owner@cedar-demo.com / #{PASSWORD}"
    puts "owner@sample.com / #{PASSWORD}"
    puts "gm@cedar-demo.com / #{PASSWORD}"
    puts "frontdesk@cedar-demo.com / #{PASSWORD}"
    puts "reservations@coastline-demo.com / #{PASSWORD}"
    puts "owner@aurora-demo.com / #{PASSWORD}"
    puts "owner@riverstone-demo.com / #{PASSWORD}"

    DemoSeedLog.section("Demo seeding complete")
  end

  def ensure_permissions_and_templates
    DemoSeedLog.section("Permissions and templates")

    PERMISSIONS.each do |attrs|
      Permission.find_or_create_by!(slug: attrs[:slug]) { |permission| permission.name = attrs[:name] }
    end

    CANCELLATION_TEMPLATES.each do |attrs|
      template = CancellationPolicyTemplate.find_or_initialize_by(name: attrs[:name])
      template.body = attrs[:body]
      template.save!
    end

    DemoSeedLog.ok("#{PERMISSIONS.size} permissions ready")
    DemoSeedLog.ok("#{CANCELLATION_TEMPLATES.size} cancellation templates ready")
  end

  def reset_demo_scope!
    DemoSeedLog.section("Resetting prior demo records")

    Account.where(slug: DEMO_ACCOUNT_SLUGS).find_each(&:destroy!)
    ApiKey.where(name: DEMO_API_KEY_NAMES).delete_all
    WebhookEvent.where("external_id LIKE ?", "demo-%").delete_all
    AppConfig.where(key: "webhook_url").delete_all

    DemoSeedLog.ok("Removed prior demo accounts, API keys, webhook events, and webhook config")
  end

  def configure_platform_defaults
    DemoSeedLog.section("Platform defaults")

    refund_policy = RefundPolicy.first_or_initialize
    refund_policy.min_days_before_checkin = 3
    refund_policy.refund_percentage = 80.0
    refund_policy.save!

    global_margin = MarginRule.where(settable_type: nil, settable_id: nil).first_or_initialize
    global_margin.rate = 12.0
    global_margin.status = "active"
    global_margin.save!

    global_setup_fee = SetupFeeRule.where(settable_type: nil, settable_id: nil).first_or_initialize
    global_setup_fee.amount = 18.0
    global_setup_fee.currency = "MYR"
    global_setup_fee.status = "active"
    global_setup_fee.save!

    AppConfig.set("webhook_url", "https://hooks.demo.wastays.com/booking-events")

    DemoSeedLog.ok("Refund policy, global margin, setup fee, and integration webhook configured")
  end

  def seed_accounts_hotels_and_users
    DemoSeedLog.section("Accounts, hotels, and users")

    platform_account = create_account(
      slug: "demo-platform",
      name: "WAStays Demo Platform",
      status: "active",
      banking: {
        account_holder_name: "WAStays Demo Platform Sdn Bhd",
        bank_name: "Maybank",
        account_number: "7000 1122 3344"
      }
    )

    superadmin = upsert_user(
      email: "superadmin@wastays.com",
      name: "WAStays Superadmin",
      role: "superadmin",
      account: platform_account
    )

    operations_admin = upsert_user(
      email: "ops@wastays.com",
      name: "Operations Admin",
      role: "superadmin",
      account: platform_account
    )

    support_superadmin = upsert_user(
      email: "s@s.com",
      name: "Support Superadmin",
      role: "superadmin",
      account: platform_account
    )

    cedar_account = create_account(
      slug: "demo-luma-stays",
      name: "Luma Stays Group",
      status: "active",
      banking: {
        account_holder_name: "Luma Stays Group Sdn Bhd",
        bank_name: "CIMB",
        account_number: "8000 4455 6677"
      }
    )

    cedar_roles = build_roles_for(cedar_account)
    cedar_owner = upsert_user(email: "owner@cedar-demo.com", name: "Aina Hashim", role: "admin", account: cedar_account)
    sample_owner = upsert_user(email: "owner@sample.com", name: "Sample Hotel Owner", role: "admin", account: cedar_account)
    cedar_gm = upsert_user(email: "gm@cedar-demo.com", name: "Marcus Tan", role: "hotel_staff", account: cedar_account)
    cedar_frontdesk = upsert_user(email: "frontdesk@cedar-demo.com", name: "Nadia Sofea", role: "hotel_staff", account: cedar_account)

    cedar_hotel = create_hotel(
      account: cedar_account,
      name: "Cedar Grand Kuala Lumpur",
      city: "Kuala Lumpur",
      country: "Malaysia",
      status: "live",
      address: "8 Jalan Pinang, Kuala Lumpur City Centre, 50450 Kuala Lumpur",
      star_rating: 4,
      tourism_tax_enabled: true,
      tourism_tax_amount: 10.0,
      usd_conversion_rate: 4.62,
      policy: {
        check_in_time: "15:00",
        check_out_time: "12:00",
        cancellation_policy: "Free cancellation up to 3 days before arrival. Within 3 days, the first night is non-refundable."
      },
      rooms: [
        { name: "Urban Deluxe King", description: "Modern king room with workspace, rainfall shower, and city skyline view.", adults: 2, children: 1, quantity: 16, base_price: 248.0, weekend_surcharge: 36.0 },
        { name: "Family Connector Suite", description: "Two-room family suite with lounge corner and flexible bedding setup.", adults: 4, children: 2, quantity: 6, base_price: 418.0, weekend_surcharge: 48.0 },
        { name: "Club Skyline Studio", description: "Upper-floor studio with lounge access and late check-out perks.", adults: 2, children: 0, quantity: 5, base_price: 338.0, weekend_surcharge: 42.0 }
      ]
    )

    add_hotel_access(cedar_owner, cedar_hotel, cedar_roles.fetch("hotel_owner"))
    add_hotel_access(sample_owner, cedar_hotel, cedar_roles.fetch("hotel_owner"))
    add_hotel_access(cedar_gm, cedar_hotel, cedar_roles.fetch("general_manager"))
    add_hotel_access(cedar_frontdesk, cedar_hotel, cedar_roles.fetch("front_desk"))

    pending_hotel = create_hotel(
      account: cedar_account,
      name: "Ember Gardens Penang",
      city: "George Town",
      country: "Malaysia",
      status: "pending_review",
      address: "21 Lebuh Kimberley, 10100 George Town, Penang",
      star_rating: 3,
      tourism_tax_enabled: true,
      tourism_tax_amount: 10.0,
      usd_conversion_rate: 4.62,
      policy: {
        check_in_time: "14:00",
        check_out_time: "11:00",
        cancellation_policy: "Moderate cancellation with 50% refund until 48 hours before check-in."
      },
      rooms: [
        { name: "Heritage Queen", description: "Warm-toned queen room with heritage shophouse detailing.", adults: 2, children: 0, quantity: 8, base_price: 188.0, weekend_surcharge: 22.0 },
        { name: "Garden Courtyard Twin", description: "Quiet courtyard-facing twin room for short city stays.", adults: 2, children: 1, quantity: 7, base_price: 172.0, weekend_surcharge: 18.0 }
      ]
    )

    add_hotel_access(cedar_owner, pending_hotel, cedar_roles.fetch("hotel_owner"))
    add_hotel_access(sample_owner, pending_hotel, cedar_roles.fetch("hotel_owner"))

    coastline_account = create_account(
      slug: "demo-coastline-collection",
      name: "Coastline Collection",
      status: "active",
      banking: {
        account_holder_name: "Coastline Collection Sdn Bhd",
        bank_name: "RHB",
        account_number: "9000 7788 1122"
      }
    )

    coastline_roles = build_roles_for(coastline_account)
    coastline_owner = upsert_user(email: "owner@coastline-demo.com", name: "Farah Azlan", role: "admin", account: coastline_account)
    coastline_reservations = upsert_user(email: "reservations@coastline-demo.com", name: "Daniel Wong", role: "hotel_staff", account: coastline_account)

    coastline_hotel = create_hotel(
      account: coastline_account,
      name: "Nusa Marina Kota Kinabalu",
      city: "Kota Kinabalu",
      country: "Malaysia",
      status: "live",
      address: "1 Sutera Harbour Boulevard, 88100 Kota Kinabalu, Sabah",
      star_rating: 4,
      tourism_tax_enabled: true,
      tourism_tax_amount: 10.0,
      usd_conversion_rate: 4.62,
      policy: {
        check_in_time: "15:00",
        check_out_time: "12:00",
        cancellation_policy: "Fully refundable up to 5 days before arrival. No-show bookings are chargeable in full."
      },
      rooms: [
        { name: "Sea View Premier", description: "Sea-facing room with balcony seating and oversized bath.", adults: 2, children: 1, quantity: 12, base_price: 296.0, weekend_surcharge: 34.0 },
        { name: "Marina Loft", description: "Split-level loft with mezzanine sleeping area and family sofa bed.", adults: 3, children: 2, quantity: 4, base_price: 452.0, weekend_surcharge: 58.0 }
      ]
    )

    add_hotel_access(coastline_owner, coastline_hotel, coastline_roles.fetch("hotel_owner"))
    add_hotel_access(coastline_reservations, coastline_hotel, coastline_roles.fetch("reservation_staff"))

    premium_account = create_account(
      slug: "demo-aurora-signature",
      name: "Aurora Signature Collection",
      status: "active",
      banking: {
        account_holder_name: "Aurora Signature Collection Sdn Bhd",
        bank_name: "HSBC",
        account_number: "6222 1188 7700"
      }
    )

    premium_roles = build_roles_for(premium_account)
    premium_owner = upsert_user(email: "owner@aurora-demo.com", name: "Vanessa Koh", role: "admin", account: premium_account)

    premium_hotel = create_hotel(
      account: premium_account,
      name: "Aurora Crown Resort Langkawi",
      city: "Langkawi",
      country: "Malaysia",
      status: "live",
      address: "12 Jalan Pantai Tengah, 07000 Langkawi, Kedah",
      star_rating: 5,
      tourism_tax_enabled: true,
      tourism_tax_amount: 10.0,
      usd_conversion_rate: 4.62,
      policy: {
        check_in_time: "15:00",
        check_out_time: "12:00",
        cancellation_policy: "Free cancellation up to 7 days before arrival. Within 7 days, one night is chargeable."
      },
      rooms: [
        { name: "Ocean Villa King", description: "Private terrace villa with plunge pool and direct sea view.", adults: 2, children: 1, quantity: 10, base_price: 980.0, weekend_surcharge: 140.0 },
        { name: "Executive Penthouse", description: "Top-floor penthouse with lounge, pantry, and sunset deck.", adults: 4, children: 2, quantity: 3, base_price: 1_650.0, weekend_surcharge: 220.0 },
        { name: "Garden Prestige Suite", description: "Low-rise suite wrapped by tropical garden and daybed patio.", adults: 3, children: 1, quantity: 8, base_price: 740.0, weekend_surcharge: 92.0 },
        { name: "Skyline Queen Deluxe", description: "Premium queen room with high-floor skyline panorama.", adults: 2, children: 0, quantity: 14, base_price: 560.0, weekend_surcharge: 70.0 }
      ]
    )

    apply_premium_inventory_variance(premium_hotel)
    add_hotel_access(premium_owner, premium_hotel, premium_roles.fetch("hotel_owner"))

    onboarding_account = create_account(
      slug: "demo-riverstone-labs",
      name: "Riverstone Labs",
      status: "active",
      banking: {
        account_holder_name: "Riverstone Labs Sdn Bhd",
        bank_name: "Public Bank",
        account_number: "5112 9900 8877"
      }
    )

    onboarding_roles = build_roles_for(onboarding_account)
    onboarding_owner = upsert_user(email: "owner@riverstone-demo.com", name: "Izzat Rahman", role: "admin", account: onboarding_account)
    onboarding_hotel = create_hotel(
      account: onboarding_account,
      name: "Riverstone Heritage Melaka",
      city: "Melaka",
      country: "Malaysia",
      status: "inventory_incomplete",
      address: "43 Jalan Tun Tan Cheng Lock, 75200 Melaka",
      star_rating: 3,
      tourism_tax_enabled: true,
      tourism_tax_amount: 10.0,
      usd_conversion_rate: 4.62,
      policy: {
        check_in_time: "15:00",
        check_out_time: "11:00",
        cancellation_policy: "Standard cancellation policy pending final onboarding approval."
      },
      rooms: [
        { name: "Courtyard Queen", description: "Queen room facing the internal courtyard with timber shutters.", adults: 2, children: 0, quantity: 6, base_price: 168.0, weekend_surcharge: 20.0 }
      ]
    )

    add_hotel_access(onboarding_owner, onboarding_hotel, onboarding_roles.fetch("hotel_owner"))

    MarginRule.find_or_initialize_by(settable: cedar_hotel).tap do |rule|
      rule.rate = 14.5
      rule.status = "active"
      rule.save!
    end

    MarginRule.find_or_initialize_by(settable: cedar_hotel.room_types.find_by!(name: "Club Skyline Studio")).tap do |rule|
      rule.rate = 16.0
      rule.status = "active"
      rule.save!
    end

    SetupFeeRule.find_or_initialize_by(settable: cedar_hotel).tap do |rule|
      rule.amount = 25.0
      rule.currency = "MYR"
      rule.status = "active"
      rule.save!
    end

    demo_accounts = Account.where(slug: DEMO_ACCOUNT_SLUGS)
    demo_hotels = Hotel.joins(:account).where(accounts: { slug: DEMO_ACCOUNT_SLUGS })
    demo_users = User.joins(:account).where(accounts: { slug: DEMO_ACCOUNT_SLUGS }).distinct

    DemoSeedLog.ok("#{demo_accounts.count} demo accounts ready")
    DemoSeedLog.ok("#{demo_hotels.count} demo hotels ready")
    DemoSeedLog.ok("#{demo_users.count} demo users ready")

    {
      platform_account: platform_account,
      superadmin: superadmin,
      operations_admin: operations_admin,
      support_superadmin: support_superadmin,
      cedar: {
        hotel: cedar_hotel,
        owner: cedar_owner,
        sample_owner: sample_owner,
        gm: cedar_gm,
        frontdesk: cedar_frontdesk
      },
      pending_hotel: {
        hotel: pending_hotel,
        owner: cedar_owner
      },
      coastline: {
        hotel: coastline_hotel,
        owner: coastline_owner,
        reservations: coastline_reservations
      },
      premium: {
        hotel: premium_hotel,
        owner: premium_owner
      },
      onboarding: {
        hotel: onboarding_hotel,
        owner: onboarding_owner
      }
    }
  end

  def seed_quotes(contexts)
    DemoSeedLog.section("Quotes and checkout journeys")

    cedar_hotel = contexts.dig(:cedar, :hotel)
    cedar_room = cedar_hotel.room_types.find_by!(name: "Urban Deluxe King")
    coastline_hotel = contexts.dig(:coastline, :hotel)
    coastline_room = coastline_hotel.room_types.find_by!(name: "Sea View Premier")

    active_quote = recreate_record(BookingQuote, token: "demo-quote-cedar-active")
    active_quote.update!(
      hotel: cedar_hotel,
      token: "demo-quote-cedar-active",
      check_in: Date.current + 12.days,
      check_out: Date.current + 14.days,
      adults: 2,
      children: 0,
      total_amount: 496.0,
      currency: "MYR",
      status: "active",
      expires_at: 2.hours.from_now,
      guest_name: "Melissa Yap",
      guest_email: "melissa.yap@example.com",
      guest_phone: "+601133445566",
      hotel_snapshot: hotel_snapshot_for(cedar_hotel),
      cancellation_policy_snapshot: cedar_hotel.property_policy&.cancellation_policy
    )
    create_quote_item(active_quote, cedar_room, quantity: 1, subtotal: 496.0)

    expired_quote = recreate_record(BookingQuote, token: "demo-quote-coast-expired")
    expired_quote.update!(
      hotel: coastline_hotel,
      token: "demo-quote-coast-expired",
      check_in: Date.current + 20.days,
      check_out: Date.current + 23.days,
      adults: 2,
      children: 1,
      total_amount: 930.0,
      currency: "MYR",
      status: "expired",
      expires_at: 3.days.ago,
      guest_name: "Julian Park",
      guest_email: "julian.park@example.com",
      guest_phone: "+601144556677",
      hotel_snapshot: hotel_snapshot_for(coastline_hotel),
      cancellation_policy_snapshot: coastline_hotel.property_policy&.cancellation_policy
    )
    create_quote_item(expired_quote, coastline_room, quantity: 1, subtotal: 930.0)

    recreate_record(PaymentTransaction, gateway: "razorpay", external_reference: "demo-pay-active-quote").update!(
      booking_quote: active_quote,
      gateway: "razorpay",
      external_reference: "demo-pay-active-quote",
      gateway_order_id: "demo-order-active-quote",
      status: "checkout_initiated",
      payment_method: "card",
      amount_subunits: 49_600,
      currency: "MYR",
      event_source: "checkout_session",
      metadata: { quote_token: active_quote.token }
    )

    recreate_record(PaymentTransaction, gateway: "razorpay", external_reference: "demo-pay-expired-quote").update!(
      booking_quote: expired_quote,
      gateway: "razorpay",
      external_reference: "demo-pay-expired-quote",
      gateway_order_id: "demo-order-expired-quote",
      status: "failed",
      payment_method: "card",
      amount_subunits: 93_000,
      currency: "MYR",
      event_source: "checkout_session",
      error_message: "Customer abandoned payment before callback verification.",
      metadata: { quote_token: expired_quote.token }
    )

    DemoSeedLog.ok("Active and expired quote journeys ready")
  end

  def seed_bookings_and_guest_journeys(contexts)
    DemoSeedLog.section("Bookings, guests, refunds, and notes")

    cedar_hotel = contexts.dig(:cedar, :hotel)
    cedar_room = cedar_hotel.room_types.index_by(&:name)
    cedar_frontdesk = contexts.dig(:cedar, :frontdesk)
    cedar_gm = contexts.dig(:cedar, :gm)

    coastline_hotel = contexts.dig(:coastline, :hotel)
    coastline_room = coastline_hotel.room_types.index_by(&:name)
    coastline_reservations = contexts.dig(:coastline, :reservations)
    premium_hotel = contexts.dig(:premium, :hotel)
    premium_room = premium_hotel.room_types.index_by(&:name)
    premium_owner = contexts.dig(:premium, :owner)

    cedar_bookings = [
      booking_story(
        token: "WS-DMO-CED-001",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Urban Deluxe King"),
        guest: guest_profile("Noor Afiqah", "noor.afiqah@example.com", "+60182221111", "female", "Malaysia", "ic", "900101-10-1111"),
        check_in: Date.current - 34.days,
        nights: 2,
        booking_status: "completed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "collected",
        checked_in_at: 34.days.ago.change(hour: 15),
        checked_out_at: 32.days.ago.change(hour: 11),
        total_amount: 496.0,
        note_bodies: [
          { user: cedar_frontdesk, body: "Guest preferred early arrival and luggage storage before check-in." }
        ]
      ),
      booking_story(
        token: "WS-DMO-CED-002",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Family Connector Suite"),
        guest: guest_profile("Jason Lim", "jason.lim@example.com", "+60183332222", "male", "Singapore", "passport", "E1122334"),
        check_in: Date.current - 18.days,
        nights: 3,
        booking_status: "completed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "released",
        checked_in_at: 18.days.ago.change(hour: 15),
        checked_out_at: 15.days.ago.change(hour: 11),
        total_amount: 1_254.0,
        tourism_tax_applied: true
      ),
      booking_story(
        token: "WS-DMO-CED-003",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Club Skyline Studio"),
        guest: guest_profile("Priya Nair", "priya.nair@example.com", "+60184443333", "female", "India", "passport", "P7788991"),
        check_in: Date.current - 7.days,
        nights: 2,
        booking_status: "completed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "card_authorization_document",
        deposit_status: "collected",
        checked_in_at: 7.days.ago.change(hour: 16),
        checked_out_at: 5.days.ago.change(hour: 11),
        total_amount: 676.0,
        tourism_tax_applied: true,
        note_bodies: [
          { user: cedar_gm, body: "Upsold from Urban Deluxe after lounge package conversion." }
        ]
      ),
      booking_story(
        token: "WS-DMO-CED-004",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Urban Deluxe King"),
        guest: guest_profile("Khairul Anuar", "khairul.anuar@example.com", "+60185554444", "male", "Malaysia", "ic", "880202-08-2222"),
        check_in: Date.current - 1.day,
        nights: 3,
        booking_status: "checked_in",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "authorized",
        checked_in_at: 1.day.ago.change(hour: 15),
        total_amount: 744.0
      ),
      booking_story(
        token: "WS-DMO-CED-005",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Urban Deluxe King"),
        guest: guest_profile("Melissa Yap", "melissa.yap@example.com", "+601133445566", "female", "Malaysia", "ic", "940909-14-3344"),
        check_in: Date.current,
        nights: 2,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "pending",
        guarantee_method: "manual_at_hotel",
        deposit_status: "pending_at_hotel",
        total_amount: 496.0
      ),
      booking_story(
        token: "WS-DMO-CED-006",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Club Skyline Studio"),
        guest: guest_profile("Soo Jin", "soojin@example.com", "+60186665555", "female", "South Korea", "passport", "M5522144"),
        check_in: Date.current + 1.day,
        nights: 2,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "authorized",
        total_amount: 676.0,
        tourism_tax_applied: true
      ),
      booking_story(
        token: "WS-DMO-CED-007",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Family Connector Suite"),
        guest: guest_profile("Rahimah Osman", "rahimah.osman@example.com", "+60187776666", "female", "Malaysia", "ic", "850505-10-9988"),
        check_in: Date.current + 5.days,
        nights: 2,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "in_progress",
        guarantee_method: "card_authorization_document",
        deposit_status: "authorized",
        total_amount: 836.0
      ),
      booking_story(
        token: "WS-DMO-CED-008",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Urban Deluxe King"),
        guest: guest_profile("Zane Goh", "zane.goh@example.com", "+60188887777", "male", "Malaysia", "ic", "920212-14-1233"),
        check_in: Date.current + 10.days,
        nights: 2,
        booking_status: "cancelled",
        payment_status: "refunded",
        precheckin_status: "pending",
        guarantee_method: "manual_at_hotel",
        deposit_status: "released",
        total_amount: 496.0
      ),
      booking_story(
        token: "WS-DMO-CED-009",
        hotel: cedar_hotel,
        room_type: cedar_room.fetch("Club Skyline Studio"),
        guest: guest_profile("Arianna Cole", "arianna.cole@example.com", "+60189998888", "female", "Australia", "passport", "A9911552"),
        check_in: Date.current + 14.days,
        nights: 3,
        booking_status: "cancelled",
        payment_status: "refunded",
        precheckin_status: "pending",
        guarantee_method: "charge_now",
        deposit_status: "released",
        total_amount: 1_014.0,
        tourism_tax_applied: true
      )
    ]

    coast_bookings = [
      booking_story(
        token: "WS-DMO-CST-001",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Sea View Premier"),
        guest: guest_profile("Lim Wei Jian", "weijian.lim@example.com", "+60191112222", "male", "Malaysia", "ic", "890909-12-1111"),
        check_in: Date.current - 29.days,
        nights: 2,
        booking_status: "completed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "released",
        checked_in_at: 29.days.ago.change(hour: 15),
        checked_out_at: 27.days.ago.change(hour: 11),
        total_amount: 592.0
      ),
      booking_story(
        token: "WS-DMO-CST-002",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Marina Loft"),
        guest: guest_profile("Angela Torres", "angela.torres@example.com", "+60192223333", "female", "Philippines", "passport", "P6677812"),
        check_in: Date.current - 12.days,
        nights: 2,
        booking_status: "completed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "collected",
        checked_in_at: 12.days.ago.change(hour: 16),
        checked_out_at: 10.days.ago.change(hour: 11),
        total_amount: 904.0,
        tourism_tax_applied: true
      ),
      booking_story(
        token: "WS-DMO-CST-003",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Sea View Premier"),
        guest: guest_profile("Yusuf Hakim", "yusuf.hakim@example.com", "+60193334444", "male", "Malaysia", "ic", "910101-12-4444"),
        check_in: Date.current - 1.day,
        nights: 2,
        booking_status: "checked_in",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "authorized",
        checked_in_at: 1.day.ago.change(hour: 15),
        total_amount: 592.0
      ),
      booking_story(
        token: "WS-DMO-CST-004",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Sea View Premier"),
        guest: guest_profile("Megan Chua", "megan.chua@example.com", "+60194445555", "female", "Malaysia", "ic", "950505-12-8877"),
        check_in: Date.current,
        nights: 3,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "pending",
        guarantee_method: "manual_at_hotel",
        deposit_status: "pending_at_hotel",
        total_amount: 888.0
      ),
      booking_story(
        token: "WS-DMO-CST-005",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Marina Loft"),
        guest: guest_profile("Kenji Watanabe", "kenji.watanabe@example.com", "+60195556666", "male", "Japan", "passport", "J9912455"),
        check_in: Date.current + 8.days,
        nights: 2,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "pending",
        guarantee_method: "card_authorization_document",
        deposit_status: "authorized",
        total_amount: 904.0,
        tourism_tax_applied: true
      ),
      booking_story(
        token: "WS-DMO-CST-006",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Sea View Premier"),
        guest: guest_profile("Adam Fitzpatrick", "adam.fitzpatrick@example.com", "+60196667777", "male", "United Kingdom", "passport", "UK441122"),
        check_in: Date.current + 16.days,
        nights: 2,
        booking_status: "cancelled",
        payment_status: "refunded",
        precheckin_status: "pending",
        guarantee_method: "charge_now",
        deposit_status: "released",
        total_amount: 592.0,
        tourism_tax_applied: true
      ),
      booking_story(
        token: "WS-DMO-CST-007",
        hotel: coastline_hotel,
        room_type: coastline_room.fetch("Marina Loft"),
        guest: guest_profile("Nur Atiqah", "nur.atiqah@example.com", "+60197778888", "female", "Malaysia", "ic", "960606-12-7766"),
        check_in: Date.current + 18.days,
        nights: 2,
        booking_status: "cancelled",
        payment_status: "refunded",
        precheckin_status: "pending",
        guarantee_method: "charge_now",
        deposit_status: "released",
        total_amount: 904.0
      )
    ]

    premium_bookings = [
      booking_story(
        token: "WS-DMO-AUR-001",
        hotel: premium_hotel,
        room_type: premium_room.fetch("Ocean Villa King"),
        guest: guest_profile("Natalie Chong", "natalie.chong@example.com", "+60194550990", "female", "Malaysia", "ic", "921212-10-4455"),
        check_in: Date.current - 9.days,
        nights: 3,
        booking_status: "completed",
        payment_status: "captured",
        precheckin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "released",
        checked_in_at: 9.days.ago.change(hour: 15),
        checked_out_at: 6.days.ago.change(hour: 11),
        total_amount: 2_940.0
      ),
      booking_story(
        token: "WS-DMO-AUR-002",
        hotel: premium_hotel,
        room_type: premium_room.fetch("Executive Penthouse"),
        guest: guest_profile("Leonard Ho", "leonard.ho@example.com", "+60195520119", "male", "Singapore", "passport", "S8871201"),
        check_in: Date.current,
        nights: 2,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "failed",
        guarantee_method: "card_authorization_document",
        deposit_status: "authorized",
        total_amount: 3_300.0,
        tourism_tax_applied: true,
        note_bodies: [
          { user: premium_owner, body: "Today edge-case: check-in on hold pending manual ID re-verification after OCR mismatch." }
        ]
      ),
      booking_story(
        token: "WS-DMO-AUR-003",
        hotel: premium_hotel,
        room_type: premium_room.fetch("Garden Prestige Suite"),
        guest: guest_profile("Samantha Lee", "samantha.lee@example.com", "+60197720444", "female", "Australia", "passport", "A7729100"),
        check_in: Date.current + 4.days,
        nights: 3,
        booking_status: "confirmed",
        payment_status: "captured",
        precheckin_status: "in_progress",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "authorized",
        total_amount: 2_220.0,
        tourism_tax_applied: true
      )
    ]

    all_stories = cedar_bookings + coast_bookings + premium_bookings
    bookings = all_stories.index_with { |story| create_booking(story) }

    create_refund_request(bookings.fetch(cedar_bookings[7]), status: "completed", refund_amount: 396.8, hotel_note: "Refund completed to original payout bank account within 3 working days.")
    create_refund_request(bookings.fetch(cedar_bookings[8]), status: "pending", refund_amount: 811.2, hotel_note: "Awaiting finance review because the booking included a prepaid lounge add-on.")
    create_refund_request(bookings.fetch(coast_bookings[5]), status: "rejected", refund_amount: 473.6, hotel_note: "Rejected because booking was cancelled after the non-refundable window.")
    create_refund_request(bookings.fetch(coast_bookings[6]), status: "approved", refund_amount: 723.2, hotel_note: "Approved and queued for payout in the next refund batch.")

    create_payment_transaction_for_booking(bookings.fetch(cedar_bookings[0]), "demo-pay-booking-ced-001")
    create_payment_transaction_for_booking(bookings.fetch(cedar_bookings[3]), "demo-pay-booking-ced-004")
    create_payment_transaction_for_booking(bookings.fetch(coast_bookings[2]), "demo-pay-booking-cst-003")
    create_payment_transaction_for_booking(bookings.fetch(premium_bookings[0]), "demo-pay-booking-aur-001")
    create_payment_retry_for_booking(
      bookings.fetch(premium_bookings[1]),
      failed_external_reference: "demo-pay-booking-aur-002-attempt-1",
      captured_external_reference: "demo-pay-booking-aur-002-attempt-2",
      failure_reason: "3DS verification timeout on first checkout attempt."
    )

    DemoSeedLog.ok("#{Booking.count} bookings ready")
    DemoSeedLog.ok("#{Guest.count} guests ready")
    DemoSeedLog.ok("#{RefundRequest.count} refund requests ready")
  end

  def seed_requests(contexts)
    DemoSeedLog.section("Operational requests")

    cedar_hotel = contexts.dig(:cedar, :hotel)
    coast_hotel = contexts.dig(:coastline, :hotel)
    premium_hotel = contexts.dig(:premium, :hotel)

    cedar_checked_in = Booking.find_by!(confirmation_token: "WS-DMO-CED-004")
    cedar_today_arrival = Booking.find_by!(confirmation_token: "WS-DMO-CED-005")
    coast_checked_in = Booking.find_by!(confirmation_token: "WS-DMO-CST-003")
    coast_today_arrival = Booking.find_by!(confirmation_token: "WS-DMO-CST-004")

    create_housekeeping_request(
      booking: cedar_checked_in,
      external_id: "demo-housekeeping-cedar-pending",
      details: "Fresh towels and one extra pillow requested after airport arrival.",
      status: "pending",
      requested_at: 2.hours.ago
    )

    create_housekeeping_request(
      booking: cedar_today_arrival,
      external_id: "demo-housekeeping-cedar-completed",
      details: "Early room refresh before VIP check-in.",
      status: "completed",
      requested_at: 1.day.ago,
      completed_at: 6.hours.ago,
      archived_at: 1.hour.ago,
      internal_notes: [ note_entry("Priority handled before 2pm arrival window.", "Nadia Sofea") ]
    )

    create_housekeeping_request(
      booking: coast_checked_in,
      external_id: "demo-housekeeping-coast-in-progress",
      details: "Mini-bar restock and balcony cleaning in progress.",
      status: "in_progress",
      requested_at: 90.minutes.ago,
      internal_notes: [ note_entry("Engineering already informed about balcony drain check.", "Daniel Wong") ]
    )

    create_housekeeping_request(
      booking: coast_today_arrival,
      external_id: "demo-housekeeping-coast-cancelled",
      details: "Turn-down service requested but cancelled by guest after flight delay.",
      status: "cancelled",
      requested_at: 5.hours.ago,
      archived_at: 30.minutes.ago,
      internal_notes: [ note_entry("Cancelled after guest updated ETA to midnight.", "Daniel Wong") ]
    )

    create_complaint_request(
      booking: cedar_checked_in,
      external_id: "demo-complaint-cedar-in-progress",
      details: "Air conditioning fluctuates after midnight.",
      status: "in_progress",
      requested_at: 3.hours.ago,
      internal_notes: [ note_entry("Engineering dispatched to inspect thermostat.", "Marcus Tan") ]
    )

    create_complaint_request(
      booking: coast_checked_in,
      external_id: "demo-complaint-coast-resolved",
      details: "TV channel list not syncing with updated remote.",
      status: "resolved",
      requested_at: 1.day.ago,
      completed_at: 12.hours.ago,
      archived_at: 15.minutes.ago,
      internal_notes: [ note_entry("Resolved after firmware reset and room revisit.", "Daniel Wong") ]
    )

    create_complaint_request(
      booking: coast_today_arrival,
      external_id: "demo-complaint-coast-failed",
      details: "Airport transfer coordination missed original pick-up slot.",
      status: "failed",
      requested_at: 6.hours.ago,
      internal_notes: [ note_entry("Guest offered food voucher while transport issue is escalated.", "Farah Azlan") ]
    )

    create_inventory_audit_log(
      hotel: cedar_hotel,
      room_type: cedar_hotel.room_types.find_by!(name: "Club Skyline Studio"),
      user: contexts.dig(:cedar, :gm),
      action_type: "bulk_rate_update",
      old_value: { base_price: 338.0 },
      new_value: { base_price: 356.0 },
      metadata: { reason: "Concert weekend demand uplift" }
    )

    create_inventory_audit_log(
      hotel: coast_hotel,
      room_type: coast_hotel.room_types.find_by!(name: "Sea View Premier"),
      user: contexts.dig(:coastline, :reservations),
      action_type: "inventory_adjustment",
      old_value: { quantity: 12 },
      new_value: { quantity: 10 },
      metadata: { reason: "2 rooms blocked for maintenance rotation" }
    )

    create_inventory_audit_log(
      hotel: premium_hotel,
      room_type: premium_hotel.room_types.find_by!(name: "Executive Penthouse"),
      user: contexts.dig(:premium, :owner),
      action_type: "bulk_rate_update",
      old_value: { base_price: 1_650.0 },
      new_value: { base_price: 1_890.0 },
      metadata: { reason: "High-demand festival week yield optimization" }
    )

    DemoSeedLog.ok("#{HousekeepingRequest.count} housekeeping requests ready")
    DemoSeedLog.ok("#{ComplaintRequest.count} complaint requests ready")
    DemoSeedLog.ok("#{InventoryAuditLog.count} inventory audit logs ready")
  end

  def seed_payouts(contexts)
    DemoSeedLog.section("Payout history")

    cedar_hotel = contexts.dig(:cedar, :hotel)
    coast_hotel = contexts.dig(:coastline, :hotel)

    cedar_paid_bookings = Booking.where(confirmation_token: %w[WS-DMO-CED-001 WS-DMO-CED-002])
    cedar_upcoming_booking = Booking.find_by!(confirmation_token: "WS-DMO-CED-003")
    coast_processing_booking = Booking.find_by!(confirmation_token: "WS-DMO-CST-002")
    coast_paid_booking = Booking.find_by!(confirmation_token: "WS-DMO-CST-001")

    paid_batch = recreate_record(PayoutBatch, hotel: cedar_hotel, payout_reference: "DEMO-PAYOUT-CED-001")
    paid_batch.update!(
      hotel: cedar_hotel,
      amount: cedar_paid_bookings.sum(:net_amount),
      status: "paid",
      period_start: Date.current - 40.days,
      period_end: Date.current - 14.days,
      payout_at: 10.days.ago.change(hour: 10),
      payout_reference: "DEMO-PAYOUT-CED-001",
      metadata: { note: "Paid via weekly finance run" }
    )

    cedar_paid_bookings.each do |booking|
      booking.update!(
        payout_batch: paid_batch,
        payout_status: "paid",
        payout_at: paid_batch.payout_at,
        payout_reference: paid_batch.payout_reference
      )
    end

    processing_batch = recreate_record(PayoutBatch, hotel: coast_hotel, payout_reference: "DEMO-PAYOUT-CST-001")
    processing_batch.update!(
      hotel: coast_hotel,
      amount: coast_processing_booking.net_amount,
      status: "processing",
      period_start: Date.current - 14.days,
      period_end: Date.current - 7.days,
      payout_reference: "DEMO-PAYOUT-CST-001",
      metadata: { note: "Awaiting finance release approval" }
    )

    coast_processing_booking.update!(
      payout_batch: processing_batch,
      payout_status: "processing",
      payout_reference: processing_batch.payout_reference
    )

    coast_paid_booking.update!(
      payout_status: "paid",
      payout_at: 19.days.ago.change(hour: 11),
      payout_reference: "DEMO-PAYOUT-CST-PAID-LEGACY"
    )

    cedar_upcoming_booking.update!(
      payout_status: "pending",
      payout_batch_id: nil,
      payout_reference: nil,
      payout_at: nil
    )

    DemoSeedLog.ok("#{PayoutBatch.count} payout batches ready")
  end

  def seed_admin_surfaces(contexts)
    DemoSeedLog.section("Admin surfaces")

    recreate_record(WebhookEvent, gateway: "razorpay", external_id: "demo-webhook-pending").update!(
      gateway: "razorpay",
      external_id: "demo-webhook-pending",
      status: "pending",
      payload: {
        id: "evt_demo_pending",
        metadata: {
          quote_token: "demo-quote-cedar-active",
          guest_name: "Melissa Yap",
          guest_email: "melissa.yap@example.com",
          guest_phone: "+601133445566"
        }
      }
    )

    recreate_record(WebhookEvent, gateway: "razorpay", external_id: "demo-webhook-failed").update!(
      gateway: "razorpay",
      external_id: "demo-webhook-failed",
      status: "failed",
      error_message: "Signature verification failed on callback payload.",
      payload: {
        id: "evt_demo_failed",
        metadata: {
          quote_token: "demo-quote-coast-expired",
          guest_name: "Julian Park",
          guest_email: "julian.park@example.com",
          guest_phone: "+601144556677"
        }
      }
    )

    recreate_record(WebhookEvent, gateway: "curlec", external_id: "demo-webhook-processed").update!(
      gateway: "curlec",
      external_id: "demo-webhook-processed",
      status: "processed",
      processed_at: 2.days.ago,
      payload: {
        id: "evt_demo_processed",
        metadata: {
          quote_token: "demo-quote-cedar-active",
          guest_name: "Melissa Yap"
        }
      }
    )

    ApiKey.find_or_initialize_by(name: "Demo Global API Key").tap do |key|
      key.bearer = nil
      key.status = "active"
      key.save!
    end

    ApiKey.find_or_initialize_by(name: "Demo Cedar API Key").tap do |key|
      key.bearer = contexts.dig(:cedar, :hotel)
      key.status = "active"
      key.save!
    end

    ApiKey.find_or_initialize_by(name: "Demo Coastline API Key").tap do |key|
      key.bearer = contexts.dig(:coastline, :hotel)
      key.status = "active"
      key.save!
    end

    ApiKey.find_or_initialize_by(name: "Demo Aurora API Key").tap do |key|
      key.bearer = contexts.dig(:premium, :hotel)
      key.status = "active"
      key.save!
    end

    DemoSeedLog.ok("#{WebhookEvent.count} webhook events ready")
    DemoSeedLog.ok("#{ApiKey.count} API keys ready")
  end

  def create_account(slug:, name:, status:, banking:)
    account = Account.find_or_initialize_by(slug: slug)
    account.name = name
    account.status = status
    account.save!

    detail = account.banking_detail || account.build_banking_detail
    detail.account_holder_name = banking[:account_holder_name]
    detail.bank_name = banking[:bank_name]
    detail.account_number = banking[:account_number]
    detail.save!

    account
  end

  def build_roles_for(account)
    ROLE_TEMPLATES.each_with_object({}) do |template, memo|
      role = Role.find_or_create_by!(account: account, slug: template[:slug]) { |record| record.name = template[:name] }
      template[:permissions].each do |permission_slug|
        permission = Permission.find_by!(slug: permission_slug)
        RolePermission.find_or_create_by!(role: role, permission: permission)
      end
      memo[template[:slug]] = role
    end
  end

  def upsert_user(email:, name:, role:, account:)
    user = User.find_or_initialize_by(email: email)
    user.name = name
    user.role = role
    user.account = account
    user.password = PASSWORD
    user.password_confirmation = PASSWORD
    user.save!
    user
  end

  def create_hotel(account:, name:, city:, country:, status:, address:, star_rating:, tourism_tax_enabled:, tourism_tax_amount:, usd_conversion_rate:, policy:, rooms:)
    hotel = Hotel.find_or_initialize_by(account: account, name: name)
    hotel.city = city
    hotel.country = country
    hotel.status = status
    hotel.address = address
    hotel.star_rating = star_rating
    hotel.default_currency = "MYR"
    hotel.usd_conversion_rate = usd_conversion_rate
    hotel.tourism_tax_enabled = tourism_tax_enabled
    hotel.tourism_tax_amount = tourism_tax_amount
    hotel.save!

    property_policy = hotel.property_policy || hotel.build_property_policy
    property_policy.check_in_time = policy[:check_in_time]
    property_policy.check_out_time = policy[:check_out_time]
    property_policy.cancellation_policy = policy[:cancellation_policy]
    property_policy.currency = "MYR"
    property_policy.usd_rate = usd_conversion_rate
    property_policy.save!

    rooms.each do |attrs|
      room_type = RoomType.find_or_initialize_by(hotel: hotel, name: attrs[:name])
      room_type.description = attrs[:description]
      room_type.max_adults = attrs[:adults]
      room_type.max_children = attrs[:children]
      room_type.quantity = attrs[:quantity]
      room_type.base_price = attrs[:base_price]
      room_type.save!

      ensure_room_calendar(
        room_type,
        start_date: DATE_RANGE_START,
        end_date: DATE_RANGE_END,
        weekend_surcharge: attrs[:weekend_surcharge] || 0.0
      )
    end

    hotel
  end

  def add_hotel_access(user, hotel, role)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
  end

  def ensure_room_calendar(room_type, start_date:, end_date:, weekend_surcharge:)
    (start_date..end_date).each do |date|
      inventory = RoomInventory.find_or_initialize_by(room_type: room_type, date: date)
      inventory.quantity = date.wday == 2 ? [ room_type.quantity - 1, 1 ].max : room_type.quantity
      inventory.status = "open"
      inventory.save!

      rate = RoomRate.find_or_initialize_by(room_type: room_type, date: date)
      rate.price = room_type.base_price + (date.saturday? || date.sunday? ? weekend_surcharge : 0.0)
      rate.currency = "MYR"
      rate.save!
    end
  end

  def backfill_room_statuses
    RoomType.includes(:hotel).find_each do |room_type|
      Array(room_type.room_numbers).each do |room_number|
        room_number = room_number.to_s.strip
        next if room_number.blank?

        RoomStatus.find_or_create_by!(
          hotel: room_type.hotel,
          room_type: room_type,
          room_number: room_number
        ) do |room_status|
          room_status.status = "ready"
          room_status.last_changed_at = Time.current
          room_status.notes = "Seeded from configured room numbers"
        end
      end
    end
  end

  def apply_premium_inventory_variance(hotel)
    room_types = hotel.room_types.index_by(&:name)
    return if room_types.empty?

    sold_out_dates = (Date.current + 6.days)..(Date.current + 8.days)
    sold_out_dates.each do |date|
      inventory = RoomInventory.find_or_initialize_by(room_type: room_types.fetch("Ocean Villa King"), date: date)
      inventory.quantity = 0
      inventory.status = "closed"
      inventory.save!

      rate = RoomRate.find_or_initialize_by(room_type: room_types.fetch("Ocean Villa King"), date: date)
      rate.price = (room_types.fetch("Ocean Villa King").base_price.to_f + 240.0).round(2)
      rate.currency = "MYR"
      rate.save!
    end

    surge_dates = (Date.current + 18.days)..(Date.current + 23.days)
    surge_dates.each do |date|
      rate = RoomRate.find_or_initialize_by(room_type: room_types.fetch("Executive Penthouse"), date: date)
      rate.price = (room_types.fetch("Executive Penthouse").base_price.to_f * 1.35).round(2)
      rate.currency = "MYR"
      rate.save!
    end

    shoulder_dates = (Date.current + 35.days)..(Date.current + 45.days)
    shoulder_dates.each do |date|
      next if date.saturday? || date.sunday?

      rate = RoomRate.find_or_initialize_by(room_type: room_types.fetch("Skyline Queen Deluxe"), date: date)
      rate.price = (room_types.fetch("Skyline Queen Deluxe").base_price.to_f * 0.88).round(2)
      rate.currency = "MYR"
      rate.save!
    end

    maintenance_dates = [ Date.current + 4.days, Date.current + 11.days ]
    maintenance_dates.each do |date|
      inventory = RoomInventory.find_or_initialize_by(room_type: room_types.fetch("Garden Prestige Suite"), date: date)
      inventory.quantity = 0
      inventory.status = "closed"
      inventory.save!
    end
  end

  def booking_story(**attrs)
    attrs
  end

  def guest_profile(name, email, phone, gender, country, document_type, government_id)
    {
      name: name,
      email: email,
      phone: phone,
      gender: gender,
      country: country,
      document_type: document_type,
      government_id: government_id
    }
  end

  def create_booking(story)
    booking = recreate_record(Booking, confirmation_token: story[:token])
    room_type = story[:room_type]
    hotel = story[:hotel]
    check_in = story[:check_in]
    check_out = check_in + story[:nights].days
    guest = upsert_guest(story[:guest])

    booking.update!(
      hotel: hotel,
      confirmation_token: story[:token],
      guest_name: story.dig(:guest, :name),
      guest_email: story.dig(:guest, :email),
      guest_phone: story.dig(:guest, :phone),
      guest_gender: story.dig(:guest, :gender),
      guest_country: story.dig(:guest, :country),
      guest_document_type: story.dig(:guest, :document_type),
      total_amount: story[:total_amount],
      currency: "MYR",
      status: story[:booking_status],
      payment_status: story[:payment_status],
      check_in: check_in,
      check_out: check_out,
      adults: room_type.max_adults >= 2 ? 2 : room_type.max_adults,
      children: room_type.max_children.positive? ? [ room_type.max_children, 1 ].min : 0,
      guarantee_method: story[:guarantee_method],
      deposit_status: story[:deposit_status],
      pre_checkin_status: story[:precheckin_status],
      hotel_snapshot: hotel_snapshot_for(hotel),
      cancellation_policy_snapshot: hotel.property_policy&.cancellation_policy,
      tourism_tax_applied: story[:tourism_tax_applied] || false,
      tourism_tax_amount: (story[:tourism_tax_applied] ? hotel.tourism_tax_amount_for(story.dig(:guest, :country)) : 0),
      checked_in_at: story[:checked_in_at],
      checked_out_at: story[:checked_out_at]
    )

    booking_margin_rate = hotel.effective_margin_rate(room_type).to_f
    margin_amount = (booking.total_amount.to_f * booking_margin_rate / 100.0).round(2)
    booking.update!(
      margin_rate: booking_margin_rate,
      margin_amount: margin_amount,
      net_amount: booking.total_amount.to_f - margin_amount,
      payout_status: booking.checked_out? ? "pending" : booking.payout_status
    )

    BookingRoom.create!(
      booking: booking,
      room_type: room_type,
      quantity: 1,
      subtotal: booking.total_amount,
      room_type_snapshot: room_type_snapshot_for(room_type),
      nightly_rate_snapshot: nightly_rate_snapshot_for(room_type, check_in, check_out),
      occupancy_snapshot: { adults: booking.adults, children: booking.children }
    )

    BookingGuest.find_or_create_by!(booking: booking, guest: guest) { |link| link.is_primary = true }

    pre_checkin = booking.pre_checkin || booking.build_pre_checkin
    pre_checkin.status = story[:precheckin_status]
    pre_checkin.document_status =
      case story[:precheckin_status]
      when "completed" then "verified"
      when "in_progress" then "uploaded"
      else "pending"
      end
    pre_checkin.signature_status = story[:precheckin_status] == "completed" ? "signed" : "pending"
    pre_checkin.completed_at = story[:precheckin_status] == "completed" ? (story[:checked_in_at] || 1.day.ago) : nil
    pre_checkin.metadata = pre_checkin_metadata_for(booking, story[:precheckin_status])
    pre_checkin.save!

    Array(story[:note_bodies]).each do |note_attrs|
      recreate_record(BookingNote, booking: booking, user: note_attrs[:user], body: note_attrs[:body]).update!(
        booking: booking,
        user: note_attrs[:user],
        body: note_attrs[:body]
      )
    end

    booking
  end

  def create_refund_request(booking, status:, refund_amount:, hotel_note:)
    refund = recreate_record(RefundRequest, booking: booking)
    refund.update!(
      booking: booking,
      reason: "Travel plan changed after booking confirmation.",
      bank_name: "Maybank",
      account_holder_name: booking.guest_name,
      account_number: "123456#{booking.id.to_s.rjust(4, '0')}",
      account_type: "savings",
      status: status,
      hotel_note: hotel_note,
      refund_amount: refund_amount
    )
  end

  def create_housekeeping_request(booking:, external_id:, details:, status:, requested_at:, completed_at: nil, archived_at: nil, internal_notes: [])
    request = recreate_record(HousekeepingRequest, external_id: external_id)
    request.update!(
      booking: booking,
      external_id: external_id,
      requested_at: requested_at,
      request_details: details,
      status: status,
      completed_at: completed_at,
      archived_at: archived_at,
      internal_notes: internal_notes,
      metadata: { source: "demo_seed" }
    )
  end

  def create_complaint_request(booking:, external_id:, details:, status:, requested_at:, completed_at: nil, archived_at: nil, internal_notes: [])
    request = recreate_record(ComplaintRequest, external_id: external_id)
    request.update!(
      booking: booking,
      external_id: external_id,
      requested_at: requested_at,
      complaint_details: details,
      status: status,
      completed_at: completed_at,
      archived_at: archived_at,
      internal_notes: internal_notes,
      metadata: { source: "demo_seed" }
    )
  end

  def create_inventory_audit_log(hotel:, room_type:, user:, action_type:, old_value:, new_value:, metadata:)
    recreate_record(
      InventoryAuditLog,
      hotel: hotel,
      room_type: room_type,
      user: user,
      action_type: action_type
    ).update!(
      hotel: hotel,
      room_type: room_type,
      user: user,
      action_type: action_type,
      old_value: old_value,
      new_value: new_value,
      metadata: metadata
    )
  end

  def create_payment_transaction_for_booking(booking, external_reference)
    recreate_record(PaymentTransaction, gateway: "razorpay", external_reference: external_reference).update!(
      booking: booking,
      gateway: "razorpay",
      external_reference: external_reference,
      gateway_order_id: "order_#{external_reference}",
      status: "captured",
      payment_method: "card",
      amount_subunits: (booking.total_amount.to_f * 100).to_i,
      currency: booking.currency,
      event_source: "client_callback",
      verified_at: booking.created_at + 2.minutes,
      captured_at: booking.created_at + 3.minutes,
      metadata: { confirmation_token: booking.confirmation_token }
    )
  end

  def create_payment_retry_for_booking(booking, failed_external_reference:, captured_external_reference:, failure_reason:)
    recreate_record(PaymentTransaction, gateway: "razorpay", external_reference: failed_external_reference).update!(
      booking: booking,
      gateway: "razorpay",
      external_reference: failed_external_reference,
      gateway_order_id: "order_#{failed_external_reference}",
      status: "failed",
      payment_method: "card",
      amount_subunits: (booking.total_amount.to_f * 100).to_i,
      currency: booking.currency,
      event_source: "client_callback",
      verified_at: booking.created_at + 1.minute,
      error_message: failure_reason,
      metadata: { confirmation_token: booking.confirmation_token, attempt: 1, retry: true }
    )

    recreate_record(PaymentTransaction, gateway: "razorpay", external_reference: captured_external_reference).update!(
      booking: booking,
      gateway: "razorpay",
      external_reference: captured_external_reference,
      gateway_order_id: "order_#{captured_external_reference}",
      status: "captured",
      payment_method: "card",
      amount_subunits: (booking.total_amount.to_f * 100).to_i,
      currency: booking.currency,
      event_source: "client_callback",
      verified_at: booking.created_at + 8.minutes,
      captured_at: booking.created_at + 9.minutes,
      metadata: { confirmation_token: booking.confirmation_token, attempt: 2, retry_of: failed_external_reference }
    )
  end

  def create_quote_item(quote, room_type, quantity:, subtotal:)
    recreate_record(BookingQuoteItem, booking_quote: quote, room_type: room_type).update!(
      booking_quote: quote,
      room_type: room_type,
      quantity: quantity,
      subtotal: subtotal,
      room_type_snapshot: room_type_snapshot_for(room_type),
      nightly_rate_snapshot: nightly_rate_snapshot_for(room_type, quote.check_in, quote.check_out),
      occupancy_snapshot: { adults: quote.adults, children: quote.children }
    )
  end

  def upsert_guest(attrs)
    guest = Guest.find_or_initialize_by(email: attrs[:email])
    guest.name = attrs[:name]
    guest.phone = attrs[:phone]
    guest.gender = attrs[:gender]
    guest.country = attrs[:country]
    guest.document_type = attrs[:document_type]
    guest.government_id = attrs[:government_id]
    guest.save!
    guest
  end

  def hotel_snapshot_for(hotel)
    {
      hotel: {
        id: hotel.id,
        name: hotel.name,
        city: hotel.city,
        country: hotel.country,
        address: hotel.address
      },
      property_policy: {
        check_in_time: hotel.property_policy&.check_in_time,
        check_out_time: hotel.property_policy&.check_out_time,
        cancellation_policy: hotel.property_policy&.cancellation_policy
      }
    }
  end

  def room_type_snapshot_for(room_type)
    {
      id: room_type.id,
      name: room_type.name,
      description: room_type.description,
      base_price: room_type.base_price.to_f,
      max_adults: room_type.max_adults,
      max_children: room_type.max_children
    }
  end

  def nightly_rate_snapshot_for(room_type, check_in, check_out)
    (check_in...check_out).map do |date|
      {
        date: date.iso8601,
        rate: RoomRate.find_by(room_type: room_type, date: date)&.price.to_f
      }
    end
  end

  def pre_checkin_metadata_for(booking, status)
    base = {
      guest_government_id: booking.primary_guest&.government_id,
      guest_country: booking.guest_country,
      submitted_at: (status == "completed" ? Time.current.iso8601 : nil),
      estimated_arrival_time: "18:30"
    }

    case status
    when "completed"
      base.merge(signature_name: booking.guest_name)
    when "in_progress"
      base.merge(document_upload_state: "passport_uploaded")
    else
      base.compact
    end
  end

  def note_entry(body, created_by_name)
    {
      "body" => body,
      "created_at" => Time.current.iso8601,
      "created_by_name" => created_by_name
    }
  end

  def recreate_record(model_class, lookup)
    existing = model_class.find_by(lookup)
    existing.destroy! if existing
    model_class.new
  end
end
