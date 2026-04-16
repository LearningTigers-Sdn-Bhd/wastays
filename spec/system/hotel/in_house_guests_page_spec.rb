require "rails_helper"

RSpec.describe "Hotel in-house guests page", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin", email: "owner@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room") }
  let(:secondary_room_type) { create(:room_type, hotel: hotel, name: "Suite Room") }

  let!(:matching_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      confirmation_token: "WS-INHOUSE-001",
      guest_name: "Aisha Tan",
      guest_email: "aisha.tan@example.com",
      guest_phone: "+60123456789",
      check_in: Date.new(2026, 4, 15),
      check_out: Date.new(2026, 4, 18),
      checked_in_at: Time.zone.local(2026, 4, 16, 10, 30),
      checked_out_at: nil,
      created_at: Time.zone.local(2026, 4, 14, 9, 0)
    )
  end

  let!(:older_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      confirmation_token: "WS-INHOUSE-002",
      guest_name: "Ben Lim",
      guest_email: "ben.lim@example.com",
      guest_phone: "+60129876543",
      check_in: Date.new(2026, 4, 14),
      check_out: Date.new(2026, 4, 17),
      checked_in_at: Time.zone.local(2026, 4, 15, 14, 0),
      checked_out_at: nil,
      created_at: Time.zone.local(2026, 4, 13, 8, 0)
    )
  end

  let!(:completed_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      confirmation_token: "WS-COMPLETED-001",
      guest_name: "Checked Out Guest",
      guest_email: "checked.out@example.com",
      guest_phone: "+60110000000",
      checked_in_at: Time.zone.local(2026, 4, 15, 11, 0),
      checked_out_at: Time.zone.local(2026, 4, 16, 10, 0)
    )
  end

  let!(:timestamp_without_status_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "confirmed",
      confirmation_token: "WS-TIMESTAMP-ONLY",
      guest_name: "Timestamp Only",
      guest_email: "timestamp@example.com",
      guest_phone: "+60116666666",
      checked_in_at: Time.zone.local(2026, 4, 16, 12, 0),
      checked_out_at: nil
    )
  end

  before do
    driven_by(:rack_test)

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    BookingRoom.create!(
      booking: matching_booking,
      room_type: room_type,
      room_type_snapshot: { "name" => room_type.name },
      quantity: 1,
      subtotal: matching_booking.total_amount
    )
    BookingRoom.create!(
      booking: older_booking,
      room_type: secondary_room_type,
      room_type_snapshot: { "name" => secondary_room_type.name },
      quantity: 2,
      subtotal: older_booking.total_amount
    )

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "renders the in-house guests board with search, summary, rows, and actions" do
    visit hotel_in_house_guests_path(hotel)

    expect(page).to have_content("In-House Guests")
    expect(page).to have_content("Guests currently checked in at your hotel.")
    expect(page).to have_content("In-House Now 2")
    expect(page).to have_field("Search in-house guests", with: "")

    rows = all("tbody tr")
    expect(rows.size).to eq(2)
    expect(rows.first).to have_content("Aisha Tan")
    expect(rows.first).to have_content("WS-INHOUSE-001")
    expect(rows.first).to have_content("aisha.tan@example.com")
    expect(rows.first).to have_content("+60123456789")
    expect(rows.first).to have_content("15 Apr 2026")
    expect(rows.first).to have_content("18 Apr 2026")
    expect(rows.first).to have_content(matching_booking.checked_in_at.in_time_zone(user.time_zone).strftime("%d %b %Y, %I:%M %p"))
    expect(rows.first).to have_content("1x Deluxe Room")
    expect(rows.first).to have_link("View booking", href: hotel_booking_path(hotel, matching_booking))
    expect(rows.first).to have_button("Check out")

    expect(page).to have_content("Ben Lim")
    expect(page).not_to have_content("Checked Out Guest")
    expect(page).not_to have_content("Timestamp Only")
  end

  it "supports query filtering, shows a clear action, and uses the check-out flow" do
    visit hotel_in_house_guests_path(hotel, query: matching_booking.confirmation_token)

    expect(page).to have_field("Search in-house guests", with: matching_booking.confirmation_token)
    expect(page).to have_link("Clear", href: hotel_in_house_guests_path(hotel))
    expect(page).to have_content("In-House Now 2")
    expect(page).to have_content("Aisha Tan")
    expect(page).not_to have_content("Ben Lim")

    within("tbody tr", text: "Aisha Tan") do
      click_button "Check out"
    end

    expect(page).to have_current_path(hotel_booking_path(hotel, matching_booking), ignore_query: true)
    expect(page).to have_content("Guest has been checked out.")
    expect(matching_booking.reload.status).to eq("completed")
    expect(matching_booking.checked_out_at).to be_present
  end

  it "keeps the real active-stay count when a search has no matches and shows search-specific empty copy" do
    visit hotel_in_house_guests_path(hotel, query: "NO-MATCH")

    expect(page).to have_field("Search in-house guests", with: "NO-MATCH")
    expect(page).to have_link("Clear", href: hotel_in_house_guests_path(hotel))
    expect(page).to have_content("In-House Now 2")
    expect(page).to have_content("No current in-house stays matched your search.")
    expect(page).to have_content("Try a different guest name, contact detail, or booking reference.")
    expect(page).not_to have_content("No guests are currently checked in.")
    expect(page).to have_css("thead th", text: "Guest / Reference")
    expect(page).to have_css("tbody tr", count: 1)
  end

  it "shows the empty state when there are no current in-house guests" do
    matching_booking.update!(status: "completed", checked_out_at: Time.current)
    older_booking.update!(status: "completed", checked_out_at: Time.current)

    visit hotel_in_house_guests_path(hotel)

    expect(page).to have_content("In-House Guests")
    expect(page).to have_content("In-House Now 0")
    expect(page).to have_content("No guests are currently checked in.")
    expect(page).to have_content("Try adjusting your search or check back after the next arrival is checked in.")
    expect(page).to have_css("thead th", text: "Guest / Reference")
    expect(page).to have_css("tbody tr", count: 1)
  end
end
