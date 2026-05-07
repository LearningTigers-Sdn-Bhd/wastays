require "rails_helper"

RSpec.describe "Hotel today's check-outs page", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin", email: "owner@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room") }
  let(:secondary_room_type) { create(:room_type, hotel: hotel, name: "Suite Room") }
  let(:today) { Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current } }

  let!(:earlier_checkout_booking) do
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
      checked_in_at: today.in_time_zone.change(hour: 11, min: 30),
      checked_out_at: today.in_time_zone.change(hour: 9, min: 30),
      created_at: today.in_time_zone.change(hour: 8, min: 0)
    )
  end

  let!(:latest_checkout_booking) do
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
      checked_out_at: today.in_time_zone.change(hour: 11, min: 45),
      created_at: today.in_time_zone.change(hour: 7, min: 0)
    )
  end

  let!(:older_completed_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      confirmation_token: "WS-OLD-001",
      guest_name: "Checked Out Earlier",
      guest_email: "checked.out@example.com",
      guest_phone: "+60110000000",
      checked_in_at: (today - 1.day).in_time_zone.change(hour: 11, min: 0),
      checked_out_at: (today - 1.day).in_time_zone.change(hour: 10, min: 0)
    )
  end

  let!(:timestamp_without_completed_status_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      confirmation_token: "WS-STILL-INHOUSE",
      guest_name: "Still Staying",
      guest_email: "staying@example.com",
      guest_phone: "+60116666666",
      checked_in_at: today.in_time_zone.change(hour: 12, min: 0),
      checked_out_at: nil
    )
  end

  before do
    driven_by(:rack_test)

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    BookingRoom.create!(
      booking: earlier_checkout_booking,
      room_type: room_type,
      room_type_snapshot: { "name" => room_type.name },
      quantity: 1,
      subtotal: earlier_checkout_booking.total_amount
    )
    BookingRoom.create!(
      booking: latest_checkout_booking,
      room_type: secondary_room_type,
      room_type_snapshot: { "name" => secondary_room_type.name },
      quantity: 2,
      subtotal: latest_checkout_booking.total_amount
    )

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "renders today's check-outs with search, summary, rows, and actions" do
    visit hotel_checked_out_guests_path(hotel)

    expect(page).to have_content("Today's Check-Outs")
    expect(page).to have_content("Guests who completed check-out today at your hotel.")
    expect(page).to have_content("Checked Out Today 2")
    expect(page).to have_field("Search today's checked-out guests", with: "")

    rows = all("tbody tr")
    expect(rows.size).to eq(2)
    expect(rows.first).to have_content("Ben Lim")
    expect(rows.first).to have_content("WS-CHECKOUT-002")
    expect(rows.first).to have_content("ben.lim@example.com")
    expect(rows.first).to have_content("+60129876543")
    expect(rows.first).to have_content((today - 3.days).strftime("%d %b %Y"))
    expect(rows.first).to have_content(today.strftime("%d %b %Y"))
    expect(rows.first).to have_content(latest_checkout_booking.checked_in_at.in_time_zone(user.time_zone).strftime("%d %b %Y, %I:%M %p"))
    expect(rows.first).to have_content(latest_checkout_booking.checked_out_at.in_time_zone(user.time_zone).strftime("%d %b %Y, %I:%M %p"))
    expect(rows.first).to have_content("2x Suite Room")
    expect(rows.first).to have_link("View booking", href: hotel_booking_path(hotel, latest_checkout_booking))

    expect(page).to have_content("Aisha Tan")
    expect(page).not_to have_content("Checked Out Earlier")
    expect(page).not_to have_content("Still Staying")
  end

  it "supports query filtering and shows a clear action" do
    visit hotel_checked_out_guests_path(hotel, query: earlier_checkout_booking.confirmation_token)

    expect(page).to have_field("Search today's checked-out guests", with: earlier_checkout_booking.confirmation_token)
    expect(page).to have_link("Clear", href: hotel_checked_out_guests_path(hotel))
    expect(page).to have_content("Checked Out Today 2")
    expect(page).to have_content("Aisha Tan")
    expect(page).not_to have_content("Ben Lim")
  end

  it "shows the empty state when there are no completed departures today" do
    earlier_checkout_booking.update!(checked_out_at: today.yesterday.in_time_zone.change(hour: 9, min: 30))
    latest_checkout_booking.update!(checked_out_at: today.yesterday.in_time_zone.change(hour: 11, min: 45))

    visit hotel_checked_out_guests_path(hotel)

    expect(page).to have_content("Today's Check-Outs")
    expect(page).to have_content("Checked Out Today 0")
    expect(page).to have_content("No guests have checked out today.")
    expect(page).to have_content("Completed departures recorded today will appear here.")
    expect(page).to have_css("thead th", text: "Guest / Reference")
    expect(page).to have_css("tbody tr", count: 1)
  end
end
