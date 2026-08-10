require 'rails_helper'

RSpec.describe BookingEngine::ReleaseExpiredHoldsJob, type: :job do
  let!(:account) { Account.create!(name: "Test Account", slug: "test-account", status: "active") }
  let!(:hotel) { Hotel.create!(sell_mode: "per_room", name: "Test Hotel", city: "Kuala Lumpur", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:check_in) { Date.today }
  let(:check_out) { Date.today + 2.days }
  let(:stay_dates) { (check_in...check_out).to_a }

  let!(:quote) do
    q = BookingQuote.create!(
      hotel: hotel,
      check_in: check_in,
      check_out: check_out,
      adults: 2,
      total_amount: 200,
      expires_at: 10.minutes.ago,
      status: 'pending'
    )
    q.booking_quote_items.create!(
      room_type: room_type,
      quantity: 1,
      subtotal: 200,
      room_type_snapshot: room_type.as_json
    )
    q
  end

  before do
    stay_dates.each do |date|
      RoomInventory.create!(room_type: room_type, date: date, quantity: 4, status: "open")
    end
  end

  it "releases the hold and updates quote status" do
    described_class.new.perform

    expect(quote.reload.status).to eq('expired')

    # Inventory should be back to 5 (4 + 1)
    stay_dates.each do |date|
      expect(room_type.room_inventories.find_by(date: date).quantity).to eq(5)
    end
  end
end
