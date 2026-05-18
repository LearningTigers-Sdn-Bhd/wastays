# frozen_string_literal: true

require_relative "demo_seeds"
require_relative "amenities"

SEED_PASSWORD = '12345678'.freeze

module SeedLog
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

module SeedData
  module_function

  def upsert_user(email:, name:, role:, account:)
    user = User.find_or_initialize_by(email: email)
    user.name = name
    user.role = role
    user.account = account
    user.password = SEED_PASSWORD
    user.password_confirmation = SEED_PASSWORD
    user.save!
    user
  end

  def ensure_role(account, template)
    role = Role.find_or_create_by!(account: account, slug: template[:slug]) do |record|
      record.name = template[:name]
    end

    template[:permissions].each do |permission_slug|
      permission = Permission.find_by!(slug: permission_slug)
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end

    role
  end

  def ensure_room_calendar(room_type, start_date:, end_date:)
    (start_date..end_date).each do |date|
      RoomInventory.find_or_create_by!(room_type: room_type, date: date) do |inventory|
        inventory.quantity = room_type.quantity
        inventory.status = 'open'
      end

      RoomRate.find_or_create_by!(room_type: room_type, date: date) do |rate|
        rate.price = room_type.base_price + (date.saturday? || date.sunday? ? 40.00 : 0.00)
        rate.currency = 'MYR'
      end
    end
  end

  def upsert_guest(guest_attrs)
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

  def create_demo_booking(hotel:, room_type:, guest_attrs:, check_in:, nights:, status:, pre_status:, guarantee:, deposit:, tourism_tax_applied: false)
    booking = Booking.create!(
      hotel: hotel,
      guest_name: guest_attrs[:name],
      guest_email: guest_attrs[:email],
      guest_phone: guest_attrs[:phone],
      guest_gender: guest_attrs[:gender],
      guest_country: guest_attrs[:country],
      guest_document_type: guest_attrs[:document_type],
      check_in: check_in,
      check_out: check_in + nights.days,
      adults: guest_attrs[:adults],
      children: guest_attrs[:children] || 0,
      currency: 'MYR',
      total_amount: room_type.base_price * nights,
      status: status,
      payment_status: 'captured',
      tourism_tax_applied: tourism_tax_applied,
      tourism_tax_amount: tourism_tax_applied ? hotel.send(:tourism_tax_amount_for, guest_attrs[:country]) : 0
    )

    BookingRoom.create!(booking: booking, room_type: room_type, quantity: 1, subtotal: room_type.base_price * nights)

    guest = upsert_guest(guest_attrs)
    BookingGuest.find_or_create_by!(booking: booking, guest: guest, is_primary: true)

    PreCheckin.find_or_create_by!(booking: booking) do |pre_checkin|
      pre_checkin.status = pre_status
      pre_checkin.document_status = pre_status == 'completed' ? 'verified' : 'pending'
      pre_checkin.signature_status = pre_status == 'completed' ? 'signed' : 'pending'
    end

    booking.update!(guarantee_method: guarantee, deposit_status: deposit)
    booking
  end
end

AmenitiesSeeder.run

if Rails.env.demo?
  DemoSeeds.run
else

SeedLog.section('Seeding WAStays data')

platform_permissions = [
  { name: 'Manage Account', slug: 'manage_account' },
  { name: 'Manage Hotel Profile', slug: 'manage_hotel_profile' },
  { name: 'Manage Room Types', slug: 'manage_room_types' },
  { name: 'Manage Rates', slug: 'manage_rates' },
  { name: 'Manage Inventory', slug: 'manage_inventory' },
  { name: 'View Bookings', slug: 'view_bookings' },
  { name: 'Manage Bookings', slug: 'manage_bookings' },
  { name: 'View Guest Phone', slug: 'view_guest_phone' },
  { name: 'Manage Guest Arrival', slug: 'manage_guest_arrival' },
  { name: 'View Audit Logs', slug: 'view_audit_logs' },
  { name: 'Export Audit Logs', slug: 'export_audit_logs' },
  { name: 'Manage Night Audit', slug: 'manage_night_audit' },
  { name: 'Manage Users', slug: 'manage_users' },
  { name: 'Manage Room Status', slug: 'manage_room_status' },
  { name: 'Post Charges', slug: 'post_charges' },
  { name: 'Post Folio Transactions', slug: 'post_folio_transactions' },
  { name: 'View Reports', slug: 'view_reports' },
  { name: 'View Payouts', slug: 'view_payouts' },
  { name: 'Manage Requests', slug: 'manage_requests' }
]

role_templates = [
  { name: 'Hotel Owner', slug: 'hotel_owner', permissions: platform_permissions.map { |p| p[:slug] } },
  { name: 'General Manager', slug: 'general_manager', permissions: platform_permissions.map { |p| p[:slug] }.reject { |s| s == 'manage_account' } },
  { name: 'Front Desk', slug: 'front_desk', permissions: %w[view_bookings manage_bookings manage_guest_arrival manage_night_audit manage_room_status post_charges post_folio_transactions manage_requests] },
  { name: 'Housekeeper', slug: 'housekeeper', permissions: %w[manage_room_status manage_requests] }
]

cancellation_templates = [
  { name: 'Flexible', body: 'Full refund if cancelled at least 24 hours before check-in time. No refund if cancelled within 24 hours.' },
  { name: 'Moderate', body: 'Full refund if cancelled at least 5 days before check-in time. 50% refund if cancelled between 2 and 5 days. No refund within 48 hours.' },
  { name: 'Strict', body: 'No refund for cancellations.' }
]

SeedLog.section('Permissions and templates')
platform_permissions.each do |permission_attrs|
  Permission.find_or_create_by!(slug: permission_attrs[:slug]) do |permission|
    permission.name = permission_attrs[:name]
  end
end
SeedLog.ok("#{platform_permissions.size} permissions ready")

cancellation_templates.each do |template_attrs|
  CancellationPolicyTemplate.find_or_create_by!(name: template_attrs[:name]) do |template|
    template.body = template_attrs[:body]
  end
end
SeedLog.ok("#{cancellation_templates.size} cancellation templates ready")

if Rails.env.development?
  SeedLog.section('Accounts, hotels, and users')

  account_blueprints = [
    {
      account: { slug: 'sample-account', name: 'Sample Account', status: 'active' },
      banking: { account_holder_name: 'Sample Hospitality Sdn Bhd', bank_name: 'Maybank', account_number: '5142 1234 5678' },
      users: [
        { email: 'owner@sample.com', name: 'Hotel Owner', role: 'admin', role_slug: 'hotel_owner' },
        { email: 'owner@example.com', name: 'Nadia Rahman', role: 'admin', role_slug: 'hotel_owner' }
      ],
      hotels: [
        {
          name: 'Sample Hotel',
          city: 'Kuala Lumpur',
          country: 'Malaysia',
          status: 'approved',
          tourism_tax_enabled: true,
          tourism_tax_amount: 10.0,
          policy: { check_in_time: '15:00', check_out_time: '12:00' },
          rooms: [
            { name: 'Deluxe Twin', description: 'A comfortable room with two twin beds, perfect for city stays.', adults: 2, children: 1, quantity: 10, base_price: 150.00 },
            { name: 'Executive King', description: 'Spacious king room with work desk and skyline view.', adults: 2, children: 1, quantity: 6, base_price: 240.00 }
          ]
        },
        {
          name: 'Aurora Hill Retreat',
          city: 'Kota Kinabalu',
          country: 'Malaysia',
          status: 'approved',
          tourism_tax_enabled: true,
          tourism_tax_amount: 10.0,
          policy: { check_in_time: '14:00', check_out_time: '12:00' },
          rooms: [
            { name: 'Skyline Suite', description: 'Suite with wraparound balcony and sunset-facing lounge.', adults: 2, children: 1, quantity: 6, base_price: 220.00 },
            { name: 'Terrace Studio', description: 'Studio with terrace lounge, rainfall shower, and work desk.', adults: 2, children: 0, quantity: 8, base_price: 180.00 }
          ]
        }
      ]
    },
    {
      account: { slug: 'borneo-boutique-group', name: 'Borneo Boutique Group', status: 'active' },
      banking: { account_holder_name: 'Borneo Boutique Group Sdn Bhd', bank_name: 'CIMB', account_number: '8000 2233 4455' },
      users: [
        { email: 'manager@borneo.test', name: 'Farid Iskandar', role: 'admin', role_slug: 'hotel_owner' }
      ],
      hotels: [
        {
          name: 'Serene Harbor Inn',
          city: 'George Town',
          country: 'Malaysia',
          status: 'approved',
          tourism_tax_enabled: true,
          tourism_tax_amount: 10.0,
          policy: { check_in_time: '14:00', check_out_time: '12:00' },
          rooms: [
            { name: 'Harbor Deluxe', description: 'Large room with harbor view and reading nook.', adults: 2, children: 1, quantity: 9, base_price: 190.00 },
            { name: 'Lantern Loft', description: 'Artistically styled loft with twin beds and heritage details.', adults: 2, children: 2, quantity: 5, base_price: 175.00 }
          ]
        },
        {
          name: 'Kinabalu Rainforest Lodge',
          city: 'Ranau',
          country: 'Malaysia',
          status: 'pending_review',
          tourism_tax_enabled: true,
          tourism_tax_amount: 10.0,
          policy: { check_in_time: '15:00', check_out_time: '11:00' },
          rooms: [
            { name: 'Canopy Cabin', description: 'Nature-facing cabin with mountain breeze and timber finishes.', adults: 2, children: 1, quantity: 4, base_price: 260.00 },
            { name: 'Garden Family Room', description: 'Family room with garden patio and two sleeping zones.', adults: 4, children: 2, quantity: 3, base_price: 320.00 }
          ]
        }
      ]
    }
  ]

  account_blueprints.each do |blueprint|
    account = Account.find_or_create_by!(slug: blueprint[:account][:slug]) do |record|
      record.name = blueprint[:account][:name]
      record.status = blueprint[:account][:status]
    end
    account.update!(name: blueprint[:account][:name], status: blueprint[:account][:status])

    role_lookup = role_templates.index_with { |template| SeedData.ensure_role(account, template) }

    BankingDetail.find_or_create_by!(account: account) do |banking_detail|
      banking_detail.account_holder_name = blueprint[:banking][:account_holder_name]
      banking_detail.bank_name = blueprint[:banking][:bank_name]
      banking_detail.account_number = blueprint[:banking][:account_number]
    end.tap do |banking_detail|
      banking_detail.update!(blueprint[:banking])
    end

    blueprint[:users].each do |user_attrs|
      user = SeedData.upsert_user(
        email: user_attrs[:email],
        name: user_attrs[:name],
        role: user_attrs[:role],
        account: account
      )

      role = role_lookup.find { |template, _| template[:slug] == user_attrs[:role_slug] }&.last
      UserRole.find_or_create_by!(user: user, role: role) if role
    end

    blueprint[:hotels].each do |hotel_attrs|
      hotel = Hotel.find_or_create_by!(account: account, name: hotel_attrs[:name]) do |record|
        record.city = hotel_attrs[:city]
        record.country = hotel_attrs[:country]
        record.status = hotel_attrs[:status]
        record.tourism_tax_enabled = hotel_attrs[:tourism_tax_enabled]
        record.tourism_tax_amount = hotel_attrs[:tourism_tax_amount]
      end

      hotel.update!(
        city: hotel_attrs[:city],
        country: hotel_attrs[:country],
        status: hotel_attrs[:status],
        tourism_tax_enabled: hotel_attrs[:tourism_tax_enabled],
        tourism_tax_amount: hotel_attrs[:tourism_tax_amount]
      )

      PropertyPolicy.find_or_create_by!(hotel: hotel) do |policy|
        policy.check_in_time = hotel_attrs[:policy][:check_in_time]
        policy.check_out_time = hotel_attrs[:policy][:check_out_time]
      end.tap do |policy|
        policy.update!(hotel_attrs[:policy])
      end

      owner_role = role_lookup.find { |template, _| template[:slug] == 'hotel_owner' }&.last
      blueprint[:users].each do |user_attrs|
        next unless user_attrs[:role_slug] == 'hotel_owner'

        user = User.find_by!(email: user_attrs[:email])
        UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: owner_role)
      end

      hotel_attrs[:rooms].each do |room_attrs|
        room_type = RoomType.find_or_create_by!(hotel: hotel, name: room_attrs[:name]) do |room|
          room.description = room_attrs[:description]
          room.max_adults = room_attrs[:adults]
          room.max_children = room_attrs[:children]
          room.quantity = room_attrs[:quantity]
          room.base_price = room_attrs[:base_price]
          room.room_number_mode = 'range'
        end

        room_type.update!(
          description: room_attrs[:description],
          max_adults: room_attrs[:adults],
          max_children: room_attrs[:children],
          quantity: room_attrs[:quantity],
          base_price: room_attrs[:base_price],
          room_number_mode: 'range'
        )

        SeedData.ensure_room_calendar(room_type, start_date: Date.current - 10.days, end_date: Date.current + 45.days)
      end
    end
  end

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

  superadmin_account = Account.find_by!(slug: 'sample-account')
  SeedData.upsert_user(email: 'superadmin@wastays.com', name: 'Super Admin', role: 'superadmin', account: superadmin_account)
  SeedData.upsert_user(email: 's@s.com', name: 'Platform Admin', role: 'superadmin', account: superadmin_account)
  SeedLog.ok('Demo users synced with password 12345678')

  SeedLog.section('Operational demo data')

  MarginRule.find_or_create_by!(settable: nil) do |rule|
    rule.rate = 12.0
    rule.status = 'active'
  end.tap do |rule|
    rule.update!(rate: 12.0, status: 'active')
  end

  failed_webhook = WebhookEvent.find_or_initialize_by(gateway: 'billplz', external_id: 'demo-failed-webhook')
  failed_webhook.status = 'failed'
  failed_webhook.error_message = 'Signature verification failed on callback payload.'
  failed_webhook.payload = { booking_reference: 'WS-DEMO-FAILED', amount: '420.00' }
  failed_webhook.save!

  processed_webhook = WebhookEvent.find_or_initialize_by(gateway: 'stripe', external_id: 'demo-processed-webhook')
  processed_webhook.status = 'processed'
  processed_webhook.error_message = nil
  processed_webhook.payload = { booking_reference: 'WS-DEMO-SUCCESS', amount: '880.00' }
  processed_webhook.save!

  bookings_to_seed = [
    {
      hotel_name: 'Sample Hotel',
      room_name: 'Deluxe Twin',
      guest: { name: 'Aisha Tan', email: 'aisha.tan@example.com', phone: '+60123456789', adults: 2, children: 0, gender: 'female', country: 'Malaysia', document_type: 'ic', government_id: '900101-10-1234' },
      check_in: Date.current - 10.days,
      nights: 2,
      status: 'completed',
      pre_status: 'completed',
      guarantee: 'pre_checkin_completed',
      deposit: 'collected',
      tourism_tax_applied: false
    },
    {
      hotel_name: 'Sample Hotel',
      room_name: 'Executive King',
      guest: { name: 'Ravi Menon', email: 'ravi.menon@example.com', phone: '+60129876543', adults: 1, children: 0, gender: 'male', country: 'India', document_type: 'passport', government_id: 'N7788991' },
      check_in: Date.current - 2.days,
      nights: 3,
      status: 'confirmed',
      pre_status: 'pending',
      guarantee: 'manual_at_hotel',
      deposit: 'pending_at_hotel',
      tourism_tax_applied: true
    },
    {
      hotel_name: 'Aurora Hill Retreat',
      room_name: 'Skyline Suite',
      guest: { name: 'Elena Cruz', email: 'elena.cruz@example.com', phone: '+60123333333', adults: 2, children: 1, gender: 'female', country: 'Philippines', document_type: 'passport', government_id: 'P3344556' },
      check_in: Date.current + 4.days,
      nights: 2,
      status: 'confirmed',
      pre_status: 'pending',
      guarantee: 'manual_at_hotel',
      deposit: 'pending_at_hotel',
      tourism_tax_applied: true
    },
    {
      hotel_name: 'Serene Harbor Inn',
      room_name: 'Harbor Deluxe',
      guest: { name: 'Nurul Iman', email: 'nurul.iman@example.com', phone: '+60194445566', adults: 2, children: 0, gender: 'female', country: 'Malaysia', document_type: 'ic', government_id: '920808-12-5566' },
      check_in: Date.current - 1.day,
      nights: 1,
      status: 'checked_in',
      pre_status: 'completed',
      guarantee: 'pre_checkin_completed',
      deposit: 'authorized',
      tourism_tax_applied: false
    },
    {
      hotel_name: 'Kinabalu Rainforest Lodge',
      room_name: 'Canopy Cabin',
      guest: { name: 'Tom Becker', email: 'tom.becker@example.com', phone: '+60192223344', adults: 2, children: 0, gender: 'male', country: 'Germany', document_type: 'passport', government_id: 'C01X7788' },
      check_in: Date.current + 9.days,
      nights: 2,
      status: 'confirmed',
      pre_status: 'pending',
      guarantee: 'card_authorization_document',
      deposit: 'authorized',
      tourism_tax_applied: true
    }
  ]

  bookings_to_seed.each do |booking_attrs|
    hotel = Hotel.find_by!(name: booking_attrs[:hotel_name])
    room_type = RoomType.find_by!(hotel: hotel, name: booking_attrs[:room_name])

    next if Booking.exists?(hotel: hotel, guest_email: booking_attrs[:guest][:email], check_in: booking_attrs[:check_in])

    booking = SeedData.create_demo_booking(
      hotel: hotel,
      room_type: room_type,
      guest_attrs: booking_attrs[:guest],
      check_in: booking_attrs[:check_in],
      nights: booking_attrs[:nights],
      status: booking_attrs[:status],
      pre_status: booking_attrs[:pre_status],
      guarantee: booking_attrs[:guarantee],
      deposit: booking_attrs[:deposit],
      tourism_tax_applied: booking_attrs[:tourism_tax_applied]
    )

    margin_rate = hotel.effective_margin_rate.to_f
    margin_amount = (booking.total_amount * (margin_rate / 100.0)).round(2)
    net_amount = booking.total_amount - margin_amount
    booking.update!(margin_rate: margin_rate, margin_amount: margin_amount, net_amount: net_amount)
  end

  SeedLog.ok("#{Account.count} accounts ready")
  SeedLog.ok("#{Hotel.count} hotels ready")
  SeedLog.ok("#{User.count} users ready")
  SeedLog.ok("#{Booking.count} bookings ready")
  SeedLog.ok("#{Guest.count} guests ready")

  SeedLog.section('Demo credentials')
  puts 'superadmin@wastays.com / 12345678'
  puts 's@s.com / 12345678'
  puts 'owner@sample.com / 12345678'
  puts 'owner@example.com / 12345678'
  puts 'manager@borneo.test / 12345678'
end

SeedLog.section('Seeding complete')
end

Hotel.find_each do |hotel|
  NotificationConfig.find_or_create_by!(hotel: hotel, notification_type: "check_in_confirmation") do |config|
    config.enabled = true
    config.channels = [ "whatsapp" ]
    config.settings = {}
  end
end
