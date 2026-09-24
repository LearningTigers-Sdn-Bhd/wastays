require "rails_helper"

RSpec.describe "Guest navigation", type: :request do
  let(:guest) { create(:guest) }
  let(:booking) { create(:booking, confirmation_token: "WS-GUEST1", check_in: Date.current + 10.days) }

  before do
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
    create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0)
    sign_in_guest!(guest)
  end

  it "titles booking detail after the reference number and goes back to My Bookings" do
    get guest_booking_path(booking)

    expect(response).to have_http_status(:success)
    expect(navbar_title).to eq(booking.formatted_reservation_number)
    expect(back_path).to eq(guest_bookings_path)
  end

  it "goes back from request refund to the booking" do
    get new_guest_booking_refund_request_path(booking)

    expect(response).to have_http_status(:success)
    expect(navbar_title).to eq("Request Refund")
    expect(back_path).to eq(guest_booking_path(booking))
  end

  it "goes back from refund detail to the booking" do
    refund_request = create(:refund_request, booking: booking)

    get guest_refund_request_path(refund_request)

    expect(response).to have_http_status(:success)
    expect(navbar_title).to eq("Refund Details")
    expect(back_path).to eq(guest_booking_path(booking))
  end

  it "falls back to the confirmation code for a booking with no reference" do
    allow_any_instance_of(Booking).to receive(:formatted_reservation_number).and_return(nil)

    get guest_booking_path(booking)

    expect(navbar_title).to eq("WS-GUEST1")
  end

  private

  def sign_in_guest!(record)
    otp = record.generate_otp!
    post guest_login_path, params: { phone: record.phone, otp: otp }
    expect(response).to redirect_to(guest_dashboard_path)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def navbar_title
    document.at_css("header.guest-navbar .guest-navbar__title")&.text&.squish
  end

  def back_path
    document.at_css("header.guest-navbar a.guest-navbar__back")&.[]("href")
  end
end
