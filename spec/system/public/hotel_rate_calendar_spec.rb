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
end
