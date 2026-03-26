# Seed Roles and Permissions

# Platform-wide Permissions
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
  { name: 'Manage Users', slug: 'manage_users' }
]

platform_permissions.each do |p|
  Permission.find_or_create_by!(slug: p[:slug]) do |perm|
    perm.name = p[:name]
  end
end

# Default Role Templates (will be used when creating an account)
ROLE_TEMPLATES = [
  { name: 'Hotel Owner', slug: 'hotel_owner', permissions: %w[manage_account manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users] },
  { name: 'General Manager', slug: 'general_manager', permissions: %w[manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users] },
  { name: 'Front Desk', slug: 'front_desk', permissions: %w[view_bookings manage_bookings manage_guest_arrival] },
  { name: 'Reservation Staff', slug: 'reservation_staff', permissions: %w[view_bookings manage_bookings view_guest_phone] }
]

# Cancellation Policy Templates
templates = [
  { name: 'Flexible', body: 'Full refund if cancelled at least 24 hours before check-in time. No refund if cancelled within 24 hours.' },
  { name: 'Moderate', body: 'Full refund if cancelled at least 5 days before check-in time. 50% refund if cancelled between 2 and 5 days. No refund within 48 hours.' },
  { name: 'Strict', body: 'No refund for cancellations.' }
]

templates.each do |t|
  CancellationPolicyTemplate.find_or_create_by!(name: t[:name]) do |template|
    template.body = t[:body]
  end
end

# Create a sample account, hotel and user if none exist (development environment)
if Rails.env.development?
  account = Account.find_or_create_by!(slug: 'sample-account') do |a|
    a.name = 'Sample Account'
    a.status = 'active'
  end

  # Create Roles for this Account
  ROLE_TEMPLATES.each do |t|
    role = Role.find_or_create_by!(account: account, slug: t[:slug]) do |r|
      r.name = t[:name]
    end

    t[:permissions].each do |p_slug|
      permission = Permission.find_by(slug: p_slug)
      RolePermission.find_or_create_by!(role: role, permission: permission) if permission
    end
  end

  hotel = Hotel.find_or_create_by!(account: account, name: 'Sample Hotel') do |h|
    h.city = 'Kuala Lumpur'
    h.country = 'Malaysia'
    h.status = 'approved'
  end

  PropertyPolicy.find_or_create_by!(hotel: hotel) do |policy|
    policy.check_in_time = '15:00'
    policy.check_out_time = '12:00'
  end

  superadmin = User.find_or_create_by!(email: 'superadmin@wastays.com') do |u|
    u.name = 'Super Admin'
    u.password = 'password'
    u.role = 'superadmin'
    u.account = account
  end

  hotel_owner_role = Role.find_by(account: account, slug: 'hotel_owner')
  
  owner = User.find_or_create_by!(email: 'owner@sample.com') do |u|
    u.name = 'Hotel Owner'
    u.password = 'password'
    u.role = 'admin'
    u.account = account
  end

  UserRole.find_or_create_by!(user: owner, role: hotel_owner_role)
  UserHotelAccess.find_or_create_by!(user: owner, hotel: hotel, role: hotel_owner_role)

  # Additional hotels for richer demo data
  extra_hotels = [
    {
      name: 'Aurora Hill Retreat',
      city: 'Kuala Terengganu',
      country: 'Malaysia',
      description: 'Clifftop retreat with panoramic Gulf views.',
      rooms: [
        { name: 'Skyline Suite', description: 'Suite with wraparound balcony', adults: 2, children: 1, quantity: 6, base_price: 220.00 },
        { name: 'Terrace Studio', description: 'Studio with terrace lounge and work desk', adults: 2, children: 0, quantity: 8, base_price: 180.00 }
      ]
    },
    {
      name: 'Serene Harbor Inn',
      city: 'George Town',
      country: 'Malaysia',
      description: 'Boutique stay beside the Penang waterfront.',
      rooms: [
        { name: 'Harbor Deluxe', description: 'Large room with harbor view', adults: 2, children: 1, quantity: 9, base_price: 190.00 },
        { name: 'Lantern Loft', description: 'Artistically styled loft with twin beds', adults: 2, children: 2, quantity: 5, base_price: 175.00 }
      ]
    }
  ]

  def seed_room_calendar(room_type, start_date:, end_date:)
    (start_date..end_date).each do |date|
      RoomInventory.find_or_create_by!(room_type: room_type, date: date) do |ri|
        ri.quantity = room_type.quantity
        ri.status = 'open'
      end

      RoomRate.find_or_create_by!(room_type: room_type, date: date) do |rr|
        rr.price = room_type.base_price + (date.saturday? || date.sunday? ? 40.00 : 0.00)
        rr.currency = 'MYR'
      end
    end
  end

  extra_hotels.each do |hotel_attrs|
    extra = Hotel.find_or_create_by!(account: account, name: hotel_attrs[:name]) do |h|
      h.city = hotel_attrs[:city]
      h.country = hotel_attrs[:country]
      h.status = 'approved'
    end

    PropertyPolicy.find_or_create_by!(hotel: extra) do |policy|
      policy.check_in_time = '14:00'
      policy.check_out_time = '12:00'
    end

      hotel_attrs[:rooms].each do |rt_attrs|
        room = RoomType.find_or_create_by!(hotel: extra, name: rt_attrs[:name]) do |rt|
          rt.description = rt_attrs[:description]
          rt.max_adults = rt_attrs[:adults]
          rt.max_children = rt_attrs[:children]
          rt.quantity = rt_attrs[:quantity]
          rt.base_price = rt_attrs[:base_price]
        end

        seed_room_calendar(room, start_date: Date.today - 5.days, end_date: Date.today + 35.days)
      end
    end

  # Seed booking history for arrivals/demo guests
  def create_demo_booking(hotel:, room_type:, guest_attrs:, check_in:, nights:, status:, pre_status:, guarantee:, deposit:)
    booking = Booking.create!(
      hotel: hotel,
      guest_name: guest_attrs[:name],
      guest_email: guest_attrs[:email],
      guest_phone: guest_attrs[:phone],
      check_in: check_in,
      check_out: check_in + nights.days,
      adults: guest_attrs[:adults],
      children: guest_attrs[:children] || 0,
      currency: 'MYR',
      total_amount: room_type.base_price * nights,
      status: status,
      payment_status: 'captured'
    )

    BookingRoom.create!(booking: booking, room_type: room_type, quantity: 1, subtotal: room_type.base_price * nights)

    guest = ActiveRecord::Encryption.without_encryption do
      Guest.find_or_create_by!(email: guest_attrs[:email]) do |g|
        g.name = guest_attrs[:name]
        g.phone = guest_attrs[:phone]
      end
    end

    BookingGuest.create!(booking: booking, guest: guest, is_primary: true)

    PreCheckin.create!(
      booking: booking,
      status: pre_status,
      document_status: pre_status == 'completed' ? 'verified' : 'pending',
      signature_status: pre_status == 'completed' ? 'signed' : 'pending'
    )

    booking.update!(guarantee_method: guarantee, deposit_status: deposit)

    booking
  end

  base_room = RoomType.find_or_create_by!(hotel: hotel, name: 'Deluxe Twin') do |rt|
    rt.description ||= 'A comfortable room with two twin beds, perfect for friends or colleagues.'
    rt.max_adults ||= 2
    rt.max_children ||= 1
    rt.quantity ||= 10
    rt.base_price ||= 150.00
  end

  seed_room_calendar(base_room, start_date: Date.today - 5.days, end_date: Date.today + 30.days)

  create_demo_booking(
    hotel: hotel,
    room_type: base_room,
    guest_attrs: { name: 'Aisha Tan', email: 'aisha.tan@example.com', phone: '+60123456789', adults: 2 },
    check_in: Date.today - 7,
    nights: 2,
    status: 'completed',
    pre_status: 'completed',
    guarantee: 'pre_checkin_completed',
    deposit: 'collected'
  )

  create_demo_booking(
    hotel: hotel,
    room_type: base_room,
    guest_attrs: { name: 'Ravi Menon', email: 'ravi.menon@example.com', phone: '+60129876543', adults: 1 },
    check_in: Date.today,
    nights: 3,
    status: 'confirmed',
    pre_status: 'pending',
    guarantee: 'manual_at_hotel',
    deposit: 'pending_at_hotel'
  )

  create_demo_booking(
    hotel: hotel,
    room_type: base_room,
    guest_attrs: { name: 'Elena Cruz', email: 'elena.cruz@example.com', phone: '+60123333333', adults: 2 },
    check_in: Date.today + 4,
    nights: 2,
    status: 'confirmed',
    pre_status: 'pending',
    guarantee: 'manual_at_hotel',
    deposit: 'pending_at_hotel'
  )

  # Create margin rules if missing
  MarginRule.find_or_create_by!(settable: nil) do |mr|
    mr.rate = 12.0
    mr.status = 'active'
  end
end
