# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions stay links", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", guest_email: "ahmad@example.com")
  end

  before do
    permission = Permission.find_by(slug: "manage_bookings") ||
      create(:permission, slug: "manage_bookings", name: "Manage bookings")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    create(:concierge_stay_access, hotel: hotel, booking: booking)
    sign_in_as(user)
  end

  it "queues the stay-link email and returns to the booking workspace" do
    destination = hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

    expect {
      post hotel_booking_action_resend_stay_link_path(hotel, booking),
        params: { return_to: destination }
    }.to have_enqueued_mail(GuestMailer, :stay_link)

    expect(response).to redirect_to(destination)
    expect(response).to have_http_status(:see_other)
    expect(flash[:notice]).to eq("Stay link sent to a•••@example.com.")
  end

  it "shows the existing send-limit error" do
    access = booking.live_concierge_stay_access
    access.update!(
      send_count: ConciergeStayAccess::MAX_SENDS,
      send_window_started_at: Time.current
    )

    expect {
      post hotel_booking_action_resend_stay_link_path(hotel, booking)
    }.not_to have_enqueued_mail(GuestMailer, :stay_link)

    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to eq(Concierge::StayAccess::SendLink::COOLDOWN)
  end

  it "requires permission to manage bookings" do
    role.role_permissions.destroy_all

    expect {
      post hotel_booking_action_resend_stay_link_path(hotel, booking)
    }.not_to have_enqueued_mail(GuestMailer, :stay_link)

    expect(response).to have_http_status(:redirect)
  end

  it "does not find a booking from another hotel" do
    other_booking = create(:booking, hotel: other_hotel, status: "checked_in", guest_email: "other@example.com")

    expect {
      post hotel_booking_action_resend_stay_link_path(hotel, other_booking)
    }.not_to have_enqueued_mail(GuestMailer, :stay_link)

    expect(response).to have_http_status(:not_found)
  end
end
