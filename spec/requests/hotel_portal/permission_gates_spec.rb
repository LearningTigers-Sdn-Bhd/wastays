# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::PermissionGates", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account, name: "Read Only", slug: "read_only") }

  before do
    role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings'))
    role.permissions << (Permission.find_by(slug: 'view_guest_records') || create(:permission, slug: 'view_guest_records'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "unified_guest_profile"), enabled: true)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  it "allows booking and guest read pages with view_bookings" do
    get hotel_bookings_path(hotel)
    expect(response).to have_http_status(:ok)

    get hotel_guests_path(hotel)
    expect(response).to have_http_status(:ok)
  end

  it "blocks booking updates without manage_bookings" do
    booking = create(:booking, hotel: hotel)

    patch hotel_booking_path(hotel, booking), params: { booking: { guest_name: "Updated" } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "blocks requests board without manage_requests" do
    get hotel_requests_path(hotel)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
  end
end
