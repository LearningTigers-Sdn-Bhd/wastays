require "rails_helper"

RSpec.describe "Hotel rate calendar", type: :system do
  let!(:account)   { Account.create!(name: "Sys RC", slug: "sys-rc", status: "active") }
  let!(:hotel)     { Hotel.create!(name: "Sys Hotel", city: "KL", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Standard", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }
  let(:today)      { Date.current }

  before do
    7.times do |i|
      date = today + i
      RoomRate.create!(room_type: room_type, date: date, price: 220, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: date, quantity: 5, status: "open")
    end
    # One sold-out day
    sold_out_date = today + 7
    RoomRate.create!(room_type: room_type, date: sold_out_date, price: 220, currency: "MYR")
    RoomInventory.create!(room_type: room_type, date: sold_out_date, quantity: 0, status: "open")
  end

  it "shows calendar with rate labels and sold-out days" do
    visit hotel_path(hotel)

    find("[data-action='click->rate-calendar#openPicker']").click

    # Calendar grid is visible
    expect(page).to have_css("[data-action*='rate-calendar#pickDay']", wait: 5)

    # Rate labels appear after async fetch
    expect(page).to have_text(/RM\s*220/, wait: 5)

    # Sold-out day has disabled styling
    expect(page).to have_css(".opacity-25", wait: 5)
  end

  it "enforces min_stay restriction by disabling check-out dates and preventing selection" do
    tomorrow = today + 1.day
    RoomRate.where(room_type: room_type, date: tomorrow).update_all(min_stay: 3)

    visit hotel_path(hotel)
    find("[data-action='click->rate-calendar#openPicker']").click

    # Click check-in date as tomorrow
    tomorrow_str = tomorrow.to_s
    find("[data-date='#{tomorrow_str}']").click

    # Check-in date should be highlighted
    expect(page).to have_css(".bg-brand-primary", text: tomorrow.day.to_s)

    # Checkout tomorrow + 1 (1 night stay) should be disabled because min stay is 3 nights
    next_day_str = (tomorrow + 1.day).to_s
    expect(page).to have_css("[data-date='#{next_day_str}'].opacity-25.cursor-not-allowed")

    # Click on the disabled date — should not set check-out or close picker
    find("[data-date='#{next_day_str}']").click
    expect(page).to have_button("Clear") # Calendar is still open

    # Tomorrow + 3 (3 nights stay) should NOT be disabled
    valid_checkout_str = (tomorrow + 3.days).to_s
    expect(page).not_to have_css("[data-date='#{valid_checkout_str}'].opacity-25.cursor-not-allowed")

    # Click on the valid check-out date — should close picker and confirm selection
    find("[data-date='#{valid_checkout_str}']").click
    expect(page).not_to have_button("Clear") # Calendar is closed
  end

  it "enforces max_stay restriction by disabling check-out dates beyond the limit" do
    tomorrow = today + 1.day
    RoomRate.where(room_type: room_type, date: tomorrow).update_all(max_stay: 2)

    visit hotel_path(hotel)
    find("[data-action='click->rate-calendar#openPicker']").click

    # Click check-in date as tomorrow
    tomorrow_str = tomorrow.to_s
    find("[data-date='#{tomorrow_str}']").click

    # Tomorrow + 3 (3 nights stay) should be disabled because max stay is 2 nights
    invalid_checkout_str = (tomorrow + 3.days).to_s
    expect(page).to have_css("[data-date='#{invalid_checkout_str}'].opacity-25.cursor-not-allowed")
  end
end
