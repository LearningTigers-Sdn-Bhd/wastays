require 'rails_helper'

RSpec.describe Public::RoomTypePresenter do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, :per_person, account: account, default_currency: "MYR") }
  let(:room_type) { create(:room_type, hotel: hotel, max_adults: 2, max_children: 2, base_price: 200.0) }
  let(:rate_plan) { room_type.standard_rate_plan }

  let(:check_in) { Date.current }
  let(:check_out) { Date.current + 2 }

  let(:service) do
    BookingEngine::AvailabilityService.new(check_in: check_in, check_out: check_out, adults: 2, children: 0)
  end

  subject(:presenter) { described_class.new(room_type, hotel, service, nil) }

  before do
    (check_in...check_out).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 3, status: "open")
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date,
                         price: 300.0, occupancy_prices: { "1" => 180.0, "2" => 300.0 })
    end
  end

  describe "#pax_occupancy_nightly_prices" do
    it "exposes the whole adult occupancy ladder so the browser preview can mirror the server" do
      expect(presenter.pax_occupancy_nightly_prices).to eq(1 => 180.0, 2 => 300.0)
    end

    it "is empty for a per-room plan, which has no ladder" do
      hotel.update!(sell_mode: "per_room")
      rate_plan.reload.update!(sell_mode: "per_room")

      expect(presenter.pax_occupancy_nightly_prices).to eq({})
    end
  end

  describe "#pax_rate_value" do
    it "derives per-person from the searched rung, not from RoomRate#price" do
      # RoomRate#price is the max-occupancy room total (300); the searched party
      # of 2 adults pays 300 for the room, so 150 each.
      expect(presenter.pax_rate_value).to eq(150.0)
    end
  end
end
