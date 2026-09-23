require "rails_helper"

RSpec.describe "Guest booking pages", type: :request do
  let(:guest) { create(:guest) }
  let(:booking) { create(:booking, status: "confirmed", check_in: Date.current + 10.days, check_out: Date.current + 12.days) }

  before do
    create(:booking_guest, guest:, booking:, is_primary: true)
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
  end

  def document = Nokogiri::HTML(response.body)

  describe "list" do
    it "lists each booking as a row and marks the active status chip" do
      get guest_bookings_path, params: { status: "confirmed", q: booking.hotel.name }

      expect(response).to have_http_status(:success)
      expect(document.css("turbo-frame#guest_bookings_results a.guest-card__row").map { |row| row["href"] })
        .to eq([ guest_booking_path(booking) ])
      active = document.at_css("nav.guest-chips a[aria-current='page']")
      expect(active.text).to eq("Confirmed")
      cancelled = document.css("nav.guest-chips a").find { |chip| chip.text == "Cancelled" }
      expect(cancelled["href"]).to include("status=cancelled", "q=")
      expect(document.at_css("form input[type='hidden'][name='status']")["value"]).to eq("confirmed")
    end

    it "says so when nothing matches" do
      get guest_bookings_path, params: { status: "cancelled" }

      expect(response.body).to include("No bookings found.")
    end
  end

  describe "detail" do
    it "shows the stay beside the documents and the refund card" do
      create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0)

      get guest_booking_path(booking)

      expect(response).to have_http_status(:success)
      summary = document.at_css(".guest-page__context .guest-stay-summary")
      expect(summary.text).to include(booking.hotel.name, booking.confirmation_token.upcase, "2 nights")
      expect(document.at_css("a.guest-card__row[href='#{receipt_guest_booking_path(booking)}']").text).to include("Booking Confirmation")
      expect(document.at_css("a.guest-card__row[href='#{summary_guest_booking_path(booking)}']")).to be_present
      expect(document.at_css("a[href='#{new_guest_booking_refund_request_path(booking, return_to: 'details')}']").text.squish)
        .to eq("Request Refund")
    end

    it "offers the Do Not Disturb switch for an assigned room while checked in" do
      in_house = create(:booking, status: "checked_in", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_guest, guest:, booking: in_house, is_primary: true)
      create(:booking_room, booking: in_house, room_type: create(:room_type, hotel: in_house.hotel), room_number: "101")

      get guest_booking_path(in_house)

      form = document.at_css("form[action='#{toggle_dnd_guest_booking_path(in_house)}']")
      expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
      expect(form.at_css("button")["aria-label"]).to eq("Turn on Do Not Disturb for room 101")
    end
  end
end
