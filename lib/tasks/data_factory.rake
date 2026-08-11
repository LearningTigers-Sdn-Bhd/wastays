# frozen_string_literal: true

module DataFactoryHelpers
  def self.section(title)
    puts "\n== #{title} #{'=' * [ 0, 72 - title.length ].max}"
  end

  def self.step(message)
    puts "-> #{Time.now.strftime('%H:%M:%S')} #{message}"
  end

  def self.ok(message)
    puts "   OK: #{message}"
  end

  def self.upsert_user(email:, name:, role:, account:)
    actual_account = account || Account.find_or_create_by!(slug: "platform-mgmt") { |a| a.name = "Platform Management"; a.status = "active" }
    user = User.find_or_initialize_by(email: email)
    user.name = name
    user.role = role
    user.account = actual_account
    user.time_zone = "Kuala Lumpur"
    user.password = "12345678"
    user.password_confirmation = "12345678"
    user.save!
    user
  end

  def self.upsert_guest(guest_attrs)
    ActiveRecord::Encryption.without_encryption do
      guest = Guest.find_or_initialize_by(email: guest_attrs[:email])
      guest.name = guest_attrs[:name]
      guest.phone = guest_attrs[:phone]
      guest.gender = guest_attrs[:gender]
      guest.country = guest_attrs[:country]
      guest.document_type = guest_attrs[:document_type]
      guest.government_id = guest_attrs[:government_id]
      guest.save!
      guest
    end
  end
end

namespace :data_factory do
  desc "Generates 3 years of comprehensive data for WAStays platform"
  task seed: :environment do
    require "faker"

    DataFactoryHelpers.section("Data Factory: 3-Year Simulation (2024-2026)")

    # 1. Setup Base Data
    setup_base_config

    # 2. Phases
    generate_phase_2024 # Early Adopters
    generate_phase_2025 # Scaling
    generate_phase_2026 # Maturity

    DataFactoryHelpers.section("Data Factory Complete!")
    summary_report
  end

  def setup_base_config
    DataFactoryHelpers.step("Setting up base configuration...")

    # Ensure Permissions
    platform_permissions = [
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
      { name: "Manage GL Mappings", slug: "manage_general_ledger_maps" },
      { name: "Manage Users", slug: "manage_users" }
    ]
    platform_permissions.each do |p|
      Permission.find_or_create_by!(slug: p[:slug]) { |perm| perm.name = p[:name] }
    end

    # Ensure Superadmins
    DataFactoryHelpers.upsert_user(email: "superadmin@wastays.com", name: "Super Admin", role: "superadmin", account: nil)

    # Ensure Global Margin Rule
    MarginRule.find_or_create_by!(settable_id: nil, settable_type: [ nil, "" ]) do |r|
      r.rate = 12.0
      r.status = "active"
    end
  end

  def generate_phase_2024
    DataFactoryHelpers.step("Phase 2024: Early Adopters...")

    hotels_data = [
      { name: "Kinabalu Pine Resort", city: "Kundasang", type: "Resort", price: 350 },
      { name: "Borneo Backpackers", city: "Kota Kinabalu", type: "Budget", price: 60 }
    ]

    hotels_data.each do |h_data|
      hotel = create_hotel_with_history(h_data, onboarded_at: Date.new(2024, 1, 1))
      simulate_bookings(hotel, start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 12, 31), density: 0.3)
      process_weekly_payouts(hotel, year: 2024)
    end
  end

  def generate_phase_2025
    DataFactoryHelpers.step("Phase 2025: Scaling Up...")

    hotels_data = [
      { name: "Gayana Marine Resort", city: "Gaya Island", type: "Luxury", price: 1200 },
      { name: "Jonker Boutique Hotel", city: "Malacca", type: "Boutique", price: 280 },
      { name: "The Majestic KL", city: "Kuala Lumpur", type: "Resort", price: 550 },
      { name: "Kuching Waterfront Lodge", city: "Kuching", type: "Budget", price: 120 },
      { name: "Semporna Water Village", city: "Semporna", type: "Resort", price: 800 }
    ]

    hotels_data.each do |h_data|
      hotel = create_hotel_with_history(h_data, onboarded_at: Date.new(2025, 1, 1))
      simulate_bookings(hotel, start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31), density: 0.5)
      process_weekly_payouts(hotel, year: 2025)
    end
  end

  def generate_phase_2026
    DataFactoryHelpers.step("Phase 2026: Maturity & Daily Operations...")

    hotels_data = [
      { name: "Mount Kinabalu Homestay", city: "Ranau", type: "Homestay", price: 150 },
      { name: "Desa Cattle Farm Stay", city: "Kundasang", type: "Homestay", price: 200 },
      { name: "Sandakan Heritage Hotel", city: "Sandakan", type: "Budget", price: 180 },
      { name: "Langkawi Sunset Villa", city: "Langkawi", type: "Luxury", price: 950 },
      { name: "Cameron Highlands Tea House", city: "Cameron Highlands", type: "Boutique", price: 400 },
      { name: "Penang Street Art Inn", city: "George Town", type: "Budget", price: 110 },
      { name: "Ipoh Old Town Suites", city: "Ipoh", type: "Boutique", price: 320 },
      { name: "Tioman Reef Resort", city: "Tioman Island", type: "Resort", price: 600 },
      { name: "Miri Marriott", city: "Miri", type: "Luxury", price: 500 },
      { name: "Tawau Hills Cabin", city: "Tawau", type: "Budget", price: 90 }
    ]

    hotels_data.each do |h_data|
      hotel = create_hotel_with_history(h_data, onboarded_at: Date.new(2026, 1, 1))
      simulate_bookings(hotel, start_date: Date.new(2026, 1, 1), end_date: Date.today, density: 0.8)
      process_weekly_payouts(hotel, year: 2026)
    end
  end

  # --- Helpers ---

  def create_hotel_with_history(data, onboarded_at:)
    account_name = "#{data[:name]} Group"
    account = Account.find_or_create_by!(slug: data[:name].parameterize) do |a|
      a.name = account_name
      a.status = "active"
      a.created_at = onboarded_at
    end

    BankingDetail.find_or_create_by!(account: account) do |b|
      b.account_holder_name = "#{account_name} Sdn Bhd"
      b.bank_name = [ "Maybank", "CIMB", "Public Bank", "RHB" ].sample
      b.account_number = Faker::Bank.account_number(digits: 12)
    end

    hotel = Hotel.find_or_create_by!(account: account, name: data[:name]) do |h|
      h.city = data[:city]
      h.country = "Malaysia"
      h.status = "live"
      h.sell_mode = "per_room"
      h.tourism_tax_enabled = true
      h.tourism_tax_amount = 10.0
      h.created_at = onboarded_at
    end

    PropertyPolicy.find_or_create_by!(hotel: hotel) do |p|
      p.check_in_time = "14:00"
      p.check_out_time = "12:00"
    end

    # Roles for the account
    owner_role = Role.find_or_create_by!(account: account, slug: "hotel_owner") { |r| r.name = "Hotel Owner" }

    # User for hotel
    user = DataFactoryHelpers.upsert_user(
      email: "owner@#{account.slug}.test",
      name: Faker::Name.name,
      role: "admin",
      account: account
    )
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: owner_role)

    # Room Types
    rt = RoomType.find_or_create_by!(hotel: hotel, name: "#{data[:type]} Standard") do |r|
      r.quantity = [ 5, 10, 15 ].sample
      r.base_price = data[:price]
      r.max_adults = 2
      r.max_children = 2
    end

    # Rates and Inventory
    (onboarded_at..(Date.today + 30.days)).each do |date|
      RoomRate.find_or_create_by!(room_type: rt, date: date) do |r|
        r.price = rt.base_price + (date.saturday? ? 50 : 0)
        r.currency = "MYR"
      end
      RoomInventory.find_or_create_by!(room_type: rt, date: date) do |i|
        i.quantity = rt.quantity
        i.status = "open"
      end
    end

    hotel
  end

  def simulate_bookings(hotel, start_date:, end_date:, density:)
    room_type = hotel.room_types.first
    current_date = start_date

    while current_date < end_date
      if rand < density
        nights = [ 1, 2, 3 ].sample
        check_out = current_date + nights.days
        status = determine_status(check_out)

        booking = Booking.create!(
          hotel: hotel,
          guest_name: Faker::Name.name,
          guest_email: Faker::Internet.email,
          guest_phone: Faker::PhoneNumber.cell_phone,
          check_in: current_date,
          check_out: check_out,
          status: status,
          payout_status: (status == "completed" ? "pending" : "none"),
          total_amount: room_type.base_price * nights,
          currency: "MYR",
          created_at: current_date - rand(2..15).days,
          adults: 2,
          children: 0
        )

        BookingRoom.create!(booking: booking, room_type: room_type, quantity: 1, subtotal: booking.total_amount)

        # Add primary guest
        guest = DataFactoryHelpers.upsert_guest(
          name: booking.guest_name,
          email: booking.guest_email,
          phone: booking.guest_phone,
          gender: [ "male", "female" ].sample,
          country: "Malaysia",
          document_type: "ic",
          government_id: "#{rand(70..99)}0101-#{rand(10..14)}-#{rand(1000..9999)}"
        )
        BookingGuest.create!(booking: booking, guest: guest, is_primary: true)

        # Financials
        margin_rate = hotel.effective_margin_rate
        margin_amt = (booking.total_amount * (margin_rate / 100.0)).round(2)
        booking.update!(
          margin_rate: margin_rate,
          margin_amount: margin_amt,
          net_amount: booking.total_amount - margin_amt,
          payment_status: "captured"
        )

        # Activity
        create_requests_and_notes(booking) if status == "completed" || status == "checked_in"
      end
      current_date += [ 1, 2 ].sample.days
    end
  end

  def determine_status(check_out)
    return "cancelled" if rand < 0.08
    return "refunded" if rand < 0.04

    if check_out < Date.today
      "completed"
    elsif check_out == Date.today
      "checked_in"
    else
      "confirmed"
    end
  end

  def create_requests_and_notes(booking)
    # Housekeeping
    if rand < 0.4
      HousekeepingRequest.create!(
        booking: booking,
        request_details: "Request: #{[ 'extra_towels', 'cleaning', 'toiletries' ].sample}. Note: #{Faker::Lorem.sentence}",
        status: [ "completed", "pending", "in_progress" ].sample,
        requested_at: booking.check_in + 4.hours,
        created_at: booking.check_in + 4.hours
      )
    end

    # Complaints
    if rand < 0.15
      ComplaintRequest.create!(
        booking: booking,
        complaint_details: "Subject: #{[ 'AC not cold', 'Noisy neighbors', 'Slow WiFi', 'No hot water' ].sample}. Details: #{Faker::Lorem.paragraph}",
        status: [ "resolved", "pending", "in_progress" ].sample,
        requested_at: booking.check_in + 6.hours,
        created_at: booking.check_in + 6.hours
      )
    end

    # Notes
    staff_user = booking.hotel.users.first || User.find_by(role: "superadmin")
    if staff_user
      BookingNote.create!(booking: booking, body: "Guest requested late check-in.", user: staff_user)
      BookingNote.create!(booking: booking, body: "Passport verified during check-in.", user: staff_user)
    end
  end

  def process_weekly_payouts(hotel, year:)
    # Group completed bookings by week of check-out
    bookings = hotel.bookings.completed.where(payout_status: "pending")
    bookings.group_by { |b| b.check_out.beginning_of_week }.each do |week_start, bs|
      period_end = week_start + 6.days
      next if period_end > Date.today # Don't batch current week yet

      payout = PayoutBatch.create!(
        hotel: hotel,
        amount: bs.sum(&:net_amount),
        status: (period_end < Date.today - 14.days ? "paid" : "processing"),
        period_start: week_start,
        period_end: period_end,
        payout_at: (period_end + 3.days),
        payout_reference: "BATCH-#{year}-W#{week_start.cweek}-#{hotel.id}"
      )
      bs.each { |b| b.update!(payout_batch: payout, payout_status: (payout.status == "paid" ? "paid" : "processing")) }
    end
  end

  def summary_report
    puts "\n--- Data Factory Summary ---"
    puts "Hotels:       #{Hotel.count}"
    puts "Bookings:     #{Booking.count} (#{Booking.completed.count} completed)"
    puts "Payouts:      #{PayoutBatch.count} batches"
    puts "Housekeeping: #{HousekeepingRequest.count} requests"
    puts "Complaints:   #{ComplaintRequest.count} requests"
    puts "Total Rev:    RM #{number_with_precision(Booking.completed.sum(:total_amount), precision: 2)}"
    puts "----------------------------"
  end

  def number_with_precision(number, precision: 2)
    ActiveSupport::NumberHelper.number_to_rounded(number, precision: precision)
  end
end
