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
    it "lists each booking as a card and marks the active status chip" do
      get guest_bookings_path, params: { status: "confirmed", q: booking.hotel.name }

      expect(response).to have_http_status(:success)
      cards = document.css("turbo-frame#guest_bookings_results a.guest-booking-card")
      expect(cards.map { |card| card["href"] }).to eq([ guest_booking_path(booking) ])
      expect(cards.first.at_css(".guest-status-badge[data-tone='info']").text.squish).to eq("Confirmed")
      expect(cards.first.at_css(".guest-booking-card__body").text).to include(booking.formatted_reservation_number, booking.confirmation_token.upcase)
      footer = cards.first.at_css(".guest-booking-card__footer").text.squish
      expect(footer).to include("Total spent MYR 0.00", "Outstanding MYR 200.00")
      active = document.at_css("nav.guest-chips a[aria-current='page']")
      expect(active.text).to eq("Confirmed")
      cancelled = document.css("nav.guest-chips a").find { |chip| chip.text == "Cancelled" }
      expect(cancelled["href"]).to include("status=cancelled", "q=")
      expect(document.at_css("form input[type='hidden'][name='status']")["value"]).to eq("confirmed")
    end

    it "offers to clear the filters when nothing matches" do
      get guest_bookings_path, params: { status: "cancelled" }

      empty = document.at_css("turbo-frame#guest_bookings_results .guest-empty-state")
      expect(empty.at_css(".guest-empty-state__title").text).to eq("No bookings match")
      expect(empty.at_css("a[href='#{guest_bookings_path}']").text.squish).to eq("Clear filters")
    end
  end

  it "finds a booking by its Ref" do
    booking.update_columns(reservation_reference: "AUR-RES-2026-00042")

    get guest_bookings_path, params: { q: "RES-2026-00042" }

    expect(document.css("a.guest-booking-card").map { |card| card["href"] }).to eq([ guest_booking_path(booking) ])
  end

  it "files a due-out stay under Checked in" do
    due_out = create(:booking, status: "due_out_detected", check_in: Date.current - 1.day, check_out: Date.current)
    create(:booking_guest, guest:, booking: due_out, is_primary: true)

    get guest_bookings_path, params: { status: "checked_in" }

    card = document.at_css("a.guest-booking-card")
    expect(card["href"]).to eq(guest_booking_path(due_out))
    expect(card.at_css(".guest-status-badge").text.squish).to eq("Checked in")
  end

  describe "detail" do
    it "shows the stay beside the documents and the refund card" do
      create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0)

      get guest_booking_path(booking)

      expect(response).to have_http_status(:success)
      summary = document.at_css(".guest-page__context .guest-stay-summary")
      expect(summary.at_css("h1").text).to eq(booking.hotel.name)
      expect(summary.text).to include(booking.formatted_reservation_number, booking.confirmation_token.upcase, "2 nights")
      concierge = summary.at_css("a[href='#{concierge_guest_booking_path(booking)}']")
      expect(concierge["target"]).to eq("_blank")
      expect(concierge.text.squish).to eq("Open concierge (opens in a new tab)")
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

  describe "open concierge" do
    it "signs an in-house guest into the stay page" do
      in_house = create(:booking, status: "checked_in", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_guest, guest:, booking: in_house, is_primary: true)
      hotel = in_house.hotel

      get concierge_guest_booking_path(in_house)

      stay_access = in_house.concierge_stay_accesses.live.first
      expect(response).to redirect_to(concierge_stay_path(hotel.unique_id, hotel.public_id, stay_access.stay_access_id))
      expect(cookies[ConciergeStaySession::COOKIE_NAME]).to be_present
    end

    it "sends a future stay to the public concierge" do
      hotel = booking.hotel

      get concierge_guest_booking_path(booking)

      expect(response).to redirect_to(concierge_home_path(hotel_code: hotel.unique_id, public_id: hotel.public_id))
      expect(booking.concierge_stay_accesses).to be_empty
    end

    it "refuses a booking that is not the guest's" do
      other = create(:booking, status: "checked_in")

      get concierge_guest_booking_path(other)

      expect(response).to redirect_to(guest_bookings_path)
      expect(other.concierge_stay_accesses).to be_empty
    end
  end
end
