require "rails_helper"

RSpec.describe PayoutExportService do
  it "exports payout batch csv rows for hotels with banking details" do
    hotel = create(:hotel)
    create(:banking_detail, account: hotel.account)
    batch = create(:payout_batch, hotel: hotel, amount: 123.45)

    csv = described_class.new([ batch ], type: :batches).generate_csv

    expect(csv).to include("Beneficiary Name")
    expect(csv).to include("BATCH-#{batch.id}")
    expect(csv).to include("123.45")
  end

  it "exports grouped booking payouts" do
    hotel = create(:hotel)
    create(:banking_detail, account: hotel.account)
    b1 = create(:booking, hotel: hotel, status: "completed", net_amount: 10.0)
    b2 = create(:booking, hotel: hotel, status: "completed", net_amount: 15.0)

    csv = described_class.new([ b1, b2 ], type: :bookings).generate_csv

    expect(csv).to include("WAStays Payout for 2 stays")
    expect(csv).to include("25.00")
  end
end
