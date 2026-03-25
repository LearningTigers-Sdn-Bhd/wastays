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
end
