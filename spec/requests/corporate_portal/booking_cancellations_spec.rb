# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::BookingCancellations", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) do
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel, account_type: "travel_agent")
  end

  def agent_booking(overrides = {})
    create(:booking, {
      hotel: hotel,
      hotel_corporate_account: relationship,
      status: "confirmed",
      payment_status: "pending",
      payment_due_at: 4.hours.from_now,
      check_in: 5.days.from_now,
      check_out: 7.days.from_now
    }.merge(overrides))
  end

  before do
    relationship
    sign_in_as(user)
  end

  describe "GET /corporate/bookings/:id/cancellation/new" do
    it "names every room that is about to go" do
      group = create(:group_booking, hotel: hotel)
      first = agent_booking(group_booking: group, group_position: 1)
      second = agent_booking(group_booking: group, group_position: 2)

      get new_corporate_booking_cancellation_path(first)

      expect(response.body).to include(first.formatted_reservation_number)
      expect(response.body).to include(second.formatted_reservation_number)
    end

    it "sends the agent back rather than showing a form it would refuse" do
      booking = agent_booking(payment_status: "captured", payment_due_at: nil)

      get new_corporate_booking_cancellation_path(booking)

      expect(response).to redirect_to(corporate_booking_path(booking))
      expect(flash[:alert]).to include("paid")
    end
  end

  describe "POST /corporate/bookings/:id/cancellation" do
    it "cancels the booking and says the rooms have gone back on sale" do
      booking = agent_booking

      post corporate_booking_cancellation_path(booking)

      expect(response).to redirect_to(corporate_booking_path(booking))
      expect(flash[:notice]).to include("returned to sale")
      expect(booking.reload.status).to eq("cancelled")
    end

    it "refuses while a transfer slip is with the hotel" do
      booking = agent_booking
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                     booking: booking, status: "pending")

      post corporate_booking_cancellation_path(booking)

      expect(flash[:alert]).to include("slip is with the hotel")
      expect(booking.reload.status).to eq("confirmed")
    end

    # The portal is the agent's own, so another agency's booking is not found
    # rather than forbidden.
    it "cannot reach another agency's booking" do
      theirs = create(:booking, hotel: hotel, hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel),
                                status: "confirmed")

      post corporate_booking_cancellation_path(theirs)

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload.status).to eq("confirmed")
    end
  end

  describe "the booking page" do
    it "offers Cancel booking while the stay is unpaid and ahead" do
      booking = agent_booking

      get corporate_booking_path(booking)

      expect(response.body).to include("Cancel booking")
    end

    it "says why instead, once the booking is paid" do
      booking = agent_booking(payment_status: "captured", payment_due_at: nil)

      get corporate_booking_path(booking)

      expect(response.body).not_to include("Cancel booking")
      expect(response.body).to include("contact the hotel to arrange a cancellation")
    end

    it "shows a cancelled booking as history rather than hiding it" do
      booking = agent_booking(status: "cancelled", payment_due_at: nil)

      get corporate_bookings_path

      expect(response.body).to include(booking.guest_name)
      expect(response.body).to include("Cancelled")
    end

    # Kept, but not competing with the bookings that still need paying.
    it "dims the cancelled row and leaves the live ones alone" do
      cancelled = agent_booking(status: "cancelled", payment_due_at: nil)
      live = agent_booking

      get corporate_bookings_path

      rows = response.parsed_body.css("li")
      cancelled_row = rows.find { |row| row.text.include?(cancelled.guest_name) }
      live_row = rows.find { |row| row.text.include?(live.guest_name) }

      expect(cancelled_row["class"]).to include("opacity-55")
      expect(live_row["class"]).not_to include("opacity-55")
    end
  end
end
