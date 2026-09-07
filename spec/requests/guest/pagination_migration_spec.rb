# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guest portal pagination migration", type: :request do
  let(:guest) { create(:guest, phone: "+60123456789") }
  let(:hotel) { create(:hotel, name: "Pagy Guest Hotel") }

  before do
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
  end

  it "paginates bookings with Pagy and preserves the active filters" do
    bookings = create_guest_bookings(26)

    get guest_bookings_path, params: { page: 2, q: "Pagy", status: "confirmed" }

    navigation = pagination_in("guest_bookings_results")
    expect(response).to have_http_status(:ok)
    expect(navigation.at_css('[aria-current="page"]').text).to eq("2")
    expect(navigation.at_css('a[aria-label="Previous page"]')["href"]).to include("q=Pagy", "status=confirmed")
    expect(response.body).to include(guest_booking_path(bookings.first))
    expect(response.body).to include("Total", "26")

    [ "invalid", "0", "-2" ].each do |invalid_page|
      get guest_bookings_path, params: { page: invalid_page }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(guest_booking_path(bookings.last))
    end

    get guest_bookings_path, params: { page: 99 }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(guest_booking_path(bookings.first), guest_booking_path(bookings.last))
  end

  it "paginates refund requests with Pagy and preserves the active filters" do
    bookings = create_guest_bookings(26, with_refunds: true)

    get guest_refund_requests_path, params: { page: 2, q: "Pagy", status: "pending" }

    navigation = pagination_in("guest_refunds_results")
    expect(response).to have_http_status(:ok)
    expect(navigation.at_css('[aria-current="page"]').text).to eq("2")
    expect(navigation.at_css('a[aria-label="Previous page"]')["href"]).to include("q=Pagy", "status=pending")
    expect(response.body).to include(bookings.first.confirmation_token)
    expect(response.body).to include("Total", "26")
  end

  private

  def create_guest_bookings(count, with_refunds: false)
    Array.new(count) do |index|
      booking = create(
        :booking,
        hotel: hotel,
        status: "confirmed",
        check_in: Date.current + index.days,
        check_out: Date.current + index.days + 1.day
      )
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:refund_request, booking: booking, status: "pending", created_at: Time.zone.local(2026, 9, 1) + index.minutes) if with_refunds
      booking
    end
  end

  def pagination_in(frame_id)
    Nokogiri::HTML(response.body).at_css("turbo-frame##{frame_id} nav.panel-pagination")
  end
end
