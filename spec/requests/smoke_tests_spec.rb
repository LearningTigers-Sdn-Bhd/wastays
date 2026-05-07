require 'rails_helper'

RSpec.describe "Platform Smoke Tests", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
  let(:staff_user) { create(:user, account: account, role: 'hotel_staff') }
  let(:superadmin) { create(:user, :superadmin) }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }
  let(:room_type) { create(:room_type, hotel: hotel) }

  before do
    # Define necessary permissions
    [
      'manage_hotel_profile', 'manage_room_types', 'manage_rates', 'manage_inventory',
      'view_bookings', 'manage_bookings', 'view_guest_phone', 'manage_guest_arrival',
      'view_audit_logs', 'view_reports', 'view_payouts'
    ].each do |slug|
      Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.humanize }
    end

    # Give role all permissions for the tests
    role.permissions << Permission.all

    # Give staff user access to the hotel
    create(:user_hotel_access, user: staff_user, hotel: hotel, role: role)

    # Setup some basic data to avoid nil errors in views
    create(:property_policy, hotel: hotel)
    room_type # ensure created
  end

  def sign_in(user)
    post login_path, params: { email: user.email, password: user.password }
  end

  describe "Superadmin Access" do
    before { sign_in(superadmin) }

    [
      "/admin/dashboard",
      "/admin/analytics",
      "/admin/hotels",
      "/admin/bookings",
      "/admin/payout_batches",
      "/admin/payouts",
      "/admin/margin_rules",
      "/admin/setup_fee_rules",
      "/admin/reconciliations",
      "/admin/audit_logs",
      "/admin/api_keys"
    ].each do |path|
      it "renders #{path} successfully" do
        get path
        expect(response).to have_http_status(:ok), "Expected #{path} to render 200 OK, but got #{response.status}"
      end
    end

    it "can also access hotel portal pages" do
      get "/hotel/#{hotel.id}/dashboard"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Hotel Staff Access" do
    before { sign_in(staff_user) }

    [
      "dashboard",
      "bookings",
      "arrivals",
      "guests",
      "in_house_guests",
      "reports",
      "reports/payouts",
      "inventory",
      "settings",
      "audit_logs"
    ].each do |subpath|
      it "renders hotel portal #{subpath} successfully" do
        path = "/hotel/#{hotel.id}/#{subpath}"
        get path
        expect(response).to have_http_status(:ok), "Expected #{path} to render 200 OK, but got #{response.status}. This usually means a missing instance variable or association in the controller/view."
      end
    end

    it "renders nested room type rates successfully" do
      path = "/hotel/#{hotel.id}/room_types/#{room_type.id}/rates"
      get path
      expect(response).to have_http_status(:ok)
    end

    it "is forbidden from accessing admin pages" do
      get "/admin/dashboard"
      # ApplicationController redirects non-superadmins to root_path with an alert
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(flash[:alert]).to include("not authorized")
    end
  end

  describe "Unauthenticated Access" do
    it "redirects to login for protected pages" do
      get "/admin/dashboard"
      expect(response).to redirect_to(login_path)
    end
  end
end
