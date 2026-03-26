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

  # Create Room Types, Inventory and Rates for Sample Hotel
  room_type = RoomType.find_or_create_by!(hotel: hotel, name: 'Deluxe Twin') do |rt|
    rt.description = 'A comfortable room with two twin beds, perfect for friends or colleagues.'
    rt.max_adults = 2
    rt.max_children = 1
    rt.quantity = 10
    rt.base_price = 150.00
  end

  # Create inventory and rates for the next 30 days
  (Date.today..(Date.today + 30.days)).each do |date|
    RoomInventory.find_or_create_by!(room_type: room_type, date: date) do |ri|
      ri.quantity = 10
      ri.status = 'open'
    end

    RoomRate.find_or_create_by!(room_type: room_type, date: date) do |rr|
      ri_price = 150.00
      ri_price += 50.00 if date.saturday? || date.sunday? # Weekend pricing
      rr.price = ri_price
      rr.currency = 'MYR'
    end
  end

  # Create default margin rule
  MarginRule.find_or_create_by!(settable: nil) do |mr|
    mr.rate = 12.0 # 12% global default
    mr.status = 'active'
  end
end
