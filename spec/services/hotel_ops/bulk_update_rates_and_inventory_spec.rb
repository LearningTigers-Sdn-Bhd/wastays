require "rails_helper"

RSpec.describe HotelOps::BulkUpdateRatesAndInventory do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:user) { create(:user, account: hotel.account) }

  it "delegates to bulk rate and inventory updaters" do
    rate_updater = instance_double(HotelOps::BulkUpdateRates, call: { success: true })
    inv_updater = instance_double(HotelOps::BulkUpdateInventory, call: { success: true })

    expect(HotelOps::BulkUpdateRates).to receive(:new).and_return(rate_updater)
    expect(HotelOps::BulkUpdateInventory).to receive(:new).and_return(inv_updater)

    result = described_class.new(
      hotel: hotel,
      room_type_ids: [ room_type.id ],
      start_date: Date.current,
      end_date: Date.current + 1,
      price: 150,
      quantity: 3,
      status: "open",
      user: user
    ).call

    expect(result[:success]).to be(true)
  end
end
