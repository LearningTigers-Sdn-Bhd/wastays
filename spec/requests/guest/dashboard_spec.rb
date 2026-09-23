require "rails_helper"

RSpec.describe "Guest dashboard", type: :request do
  let(:guest) { create(:guest, name: "Aisha Rahman") }

  before do
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
  end

  def stats
    Nokogiri::HTML(response.body).css(".guest-stat-card").to_h do |card|
      [ card.at_css(".guest-stat-card__label").text.squish, card.at_css(".guest-stat-card__value").text.squish ]
    end
  end

  it "counts every upcoming stay, not only the five it lists" do
    6.times do |index|
      stay = create(:booking, check_in: Date.current + (10 + index).days, check_out: Date.current + (11 + index).days)
      create(:booking_guest, guest:, booking: stay, is_primary: true)
    end

    get guest_dashboard_path

    expect(stats["Upcoming"]).to eq("6")
  end

  it "counts the refunds the guest asked for, and only theirs" do
    stay = create(:booking, status: "cancelled", check_in: Date.current + 10.days, check_out: Date.current + 12.days)
    create(:booking_guest, guest:, booking: stay, is_primary: true)
    create(:refund_request, booking: stay)
    create(:refund_request, booking: create(:booking, status: "cancelled"))

    get guest_dashboard_path

    expect(stats["Refunds requested"]).to eq("1")
  end

  it "splits live stays from cancelled ones, and skips a cancelled stay for the next stay" do
    { "confirmed" => 5, "cancelled" => 3, "checked_in" => 0, "due_out_detected" => -1 }.each do |status, offset|
      stay = create(:booking, status:, check_in: Date.current + offset.days, check_out: Date.current + (offset + 2).days)
      create(:booking_guest, guest:, booking: stay, is_primary: true)
    end

    get guest_dashboard_path

    expect(stats).to eq("Total bookings" => "4", "Upcoming" => "1", "In house" => "2", "Refunds requested" => "0")
    expect(Nokogiri::HTML(response.body).at_css(".guest-stay-summary__eyebrow").text).to eq("Current stay")
  end

  it "greets the guest and says there are no bookings yet" do
    get guest_dashboard_path

    expect(response).to have_http_status(:success)
    heading = Nokogiri::HTML(response.body).at_css("h1")
    expect(heading.text.squish).to eq("Hello, Aisha Rahman")
    expect(heading.at_css("span.text-primary").text).to eq("Aisha Rahman")
    expect(response.body).to include("Your stays, documents, and refunds, all in one place.")
    expect(response.body).to include("No bookings yet.")
    expect(stats).to eq("Total bookings" => "0", "Upcoming" => "0", "In house" => "0", "Refunds requested" => "0")
    expect(response.body).not_to include("Open concierge")
  end

  it "shows the next stay with its concierge, and lists the other bookings" do
    upcoming = create(:booking, check_in: Date.current + 10.days, check_out: Date.current + 12.days)
    past = create(:booking, check_in: Date.current - 20.days, check_out: Date.current - 18.days)
    create(:booking_guest, guest:, booking: upcoming, is_primary: true)
    create(:booking_guest, guest:, booking: past, is_primary: true)

    get guest_dashboard_path

    document = Nokogiri::HTML(response.body)
    summary = document.at_css(".guest-stay-summary")

    expect(summary.text).to include("Next stay", upcoming.hotel.name, "2 nights")
    concierge = summary.at_css("a[href='#{concierge_guest_booking_path(upcoming)}']")
    expect(concierge.text.squish).to eq("Open concierge (opens in a new tab)")
    expect(concierge["target"]).to eq("_blank")
    expect(summary.at_css("a[href='#{guest_booking_path(upcoming)}']").text.squish).to eq("View booking")
    expect(document.css("a.guest-booking-card").map { |card| card["href"] }).to eq([ guest_booking_path(past) ])
    expect(stats).to eq("Total bookings" => "2", "Upcoming" => "1", "In house" => "0", "Refunds requested" => "0")
  end

  it "shows only the stay card when the next stay is the only booking" do
    upcoming = create(:booking, check_in: Date.current + 10.days, check_out: Date.current + 12.days)
    create(:booking_guest, guest:, booking: upcoming, is_primary: true)

    get guest_dashboard_path

    expect(response.body).to include("Next stay")
    expect(response.body).not_to include("Recent Bookings", "No bookings yet.")
  end
end
