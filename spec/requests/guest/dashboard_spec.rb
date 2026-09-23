require "rails_helper"

RSpec.describe "Guest dashboard", type: :request do
  let(:guest) { create(:guest, name: "Aisha Rahman") }

  before do
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
  end

  it "greets the guest and says there are no bookings yet" do
    get guest_dashboard_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Hello, Aisha")
    expect(response.body).to include("No bookings yet.")
    expect(response.body).not_to include("Open concierge")
  end

  it "shows the next stay with its concierge, and lists recent bookings" do
    upcoming = create(:booking, check_in: Date.current + 10.days, check_out: Date.current + 12.days)
    past = create(:booking, check_in: Date.current - 20.days, check_out: Date.current - 18.days)
    create(:booking_guest, guest:, booking: upcoming, is_primary: true)
    create(:booking_guest, guest:, booking: past, is_primary: true)

    get guest_dashboard_path

    document = Nokogiri::HTML(response.body)
    summary = document.at_css(".guest-stay-summary")
    hotel = upcoming.hotel

    expect(summary.text).to include("Next stay", hotel.name, "2 nights")
    expect(summary.at_css("a[href='#{concierge_home_path(hotel_code: hotel.unique_id, public_id: hotel.public_id)}']")).to be_present
    expect(document.css("a.guest-card__row").map { |row| row["href"] })
      .to eq([ guest_booking_path(upcoming), guest_booking_path(past) ])
  end
end
