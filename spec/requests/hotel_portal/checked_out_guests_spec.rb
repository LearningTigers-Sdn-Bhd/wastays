require "rails_helper"

RSpec.describe "HotelPortal::CheckedOutGuests", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room") }
  let(:today) { Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current } }

  let(:early_checkout_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      confirmation_token: "WS-CHECKOUT-001",
      guest_name: "Aisha Tan",
      guest_email: "aisha.tan@example.com",
      guest_phone: "+60123456789",
      check_in: today - 2.days,
      check_out: today,
      checked_in_at: today.in_time_zone.change(hour: 11, min: 0),
      checked_out_at: today.in_time_zone.change(hour: 9, min: 15)
    )
  end

  let(:latest_checkout_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      confirmation_token: "WS-CHECKOUT-002",
      guest_name: "Ben Lim",
      guest_email: "ben.lim@example.com",
      guest_phone: "+60129876543",
      check_in: today - 3.days,
      check_out: today,
      checked_in_at: today.in_time_zone.change(hour: 10, min: 0),
      checked_out_at: today.in_time_zone.change(hour: 11, min: 45)
    )
  end

  let(:previous_day_checkout_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      confirmation_token: "WS-OLD-001",
      guest_name: "Earlier Guest",
      guest_email: "earlier@example.com",
      guest_phone: "+60111111111",
      checked_in_at: (today - 1.day).in_time_zone.change(hour: 15, min: 0),
      checked_out_at: (today - 1.day).in_time_zone.change(hour: 11, min: 0)
    )
  end

  let(:not_completed_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      confirmation_token: "WS-INHOUSE-003",
      guest_name: "Still Staying",
      guest_email: "staying@example.com",
      guest_phone: "+60122222222",
      checked_in_at: today.in_time_zone.change(hour: 13, min: 0),
      checked_out_at: nil
    )
  end

  let(:other_hotel_checkout_booking) do
    create(
      :booking,
      hotel: other_hotel,
      status: "completed",
      confirmation_token: "WS-OTHER-001",
      guest_name: "Other Hotel Guest",
      guest_email: "other.hotel@example.com",
      guest_phone: "+60144444444",
      checked_in_at: today.in_time_zone.change(hour: 12, min: 0),
      checked_out_at: today.in_time_zone.change(hour: 10, min: 30)
    )
  end

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)

    attach_booking_details(early_checkout_booking)
    attach_booking_details(latest_checkout_booking)
  end

  def attach_booking_details(booking)
    BookingRoom.create!(
      booking: booking,
      room_type: room_type,
      room_type_snapshot: { "name" => room_type.name },
      subtotal: booking.total_amount
    )
  end

  describe "GET /index" do
    it "shows only current hotel's completed bookings checked out today" do
      previous_day_checkout_booking
      not_completed_booking
      other_hotel_checkout_booking

      get hotel_checked_out_guests_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Today's Check-Outs")
      expect(response.body).to include("Guests who completed check-out today at your hotel.")
      expect(response.body).to include(early_checkout_booking.guest_name)
      expect(response.body).to include(latest_checkout_booking.guest_name)
      expect(response.body).not_to include(previous_day_checkout_booking.guest_name)
      expect(response.body).not_to include(not_completed_booking.guest_name)
      expect(response.body).not_to include(other_hotel_checkout_booking.guest_name)
    end

    it "searches today's checked-out guests by booking reference" do
      previous_day_checkout_booking

      get hotel_checked_out_guests_path(hotel), params: { query: early_checkout_booking.confirmation_token }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(early_checkout_booking.confirmation_token)
      expect(response.body).not_to include(latest_checkout_booking.confirmation_token)
      expect(response.body).not_to include(previous_day_checkout_booking.confirmation_token)
    end

    it "orders the latest check-outs first" do
      previous_day_checkout_booking

      get hotel_checked_out_guests_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body.index(latest_checkout_booking.guest_name)).to be < response.body.index(early_checkout_booking.guest_name)
    end

    it "renders the empty state when no guests checked out today" do
      early_checkout_booking.update!(checked_out_at: today.yesterday.in_time_zone.change(hour: 9, min: 15))
      latest_checkout_booking.update!(checked_out_at: today.yesterday.in_time_zone.change(hour: 11, min: 45))

      get hotel_checked_out_guests_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No guests have checked out today.")
      expect(response.body).to include("Completed departures recorded today will appear here.")
    end
  end
end
