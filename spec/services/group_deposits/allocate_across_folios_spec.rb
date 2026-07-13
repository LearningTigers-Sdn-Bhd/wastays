require "rails_helper"

RSpec.describe GroupDeposits::AllocateAcrossFolios do
  let(:group) { create(:group_booking) }
  let(:hotel) { group.hotel }
  let(:deposit) { create(:group_deposit, group_booking: group, hotel: hotel, amount: 1_000, currency: hotel.default_currency) }

  def folio_with_balance(balance)
    booking = create(:booking, hotel: hotel, group_booking: group, group_position: rand(1..999))
    create(:booking_room, booking: booking)
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, currency: deposit.currency)
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: balance) if balance.positive?
    folio
  end

  describe "manual strategy" do
    it "allocates the exact amounts requested per folio" do
      folio_a = folio_with_balance(200)
      folio_b = folio_with_balance(300)

      result = described_class.call(
        deposit: deposit, folios: [ folio_a, folio_b ], amount: 500, strategy: "manual",
        manual_amounts: { folio_a.id => 200, folio_b.id => 300 }
      )

      expect(result).to be_success
      expect(result.allocations.map(&:amount)).to contain_exactly(200.to_d, 300.to_d)
      expect(deposit.reload.available_amount).to eq(500.to_d)
    end

    it "fails when the manual plan does not sum to the requested amount" do
      folio_a = folio_with_balance(200)

      result = described_class.call(
        deposit: deposit, folios: [ folio_a ], amount: 500, strategy: "manual",
        manual_amounts: { folio_a.id => 200 }
      )

      expect(result).not_to be_success
      expect(result.error).to include("must equal")
    end
  end

  describe "outstanding_balance strategy" do
    it "fills each folio's outstanding balance in order until the amount is exhausted" do
      folio_a = folio_with_balance(300)
      folio_b = folio_with_balance(300)

      result = described_class.call(deposit: deposit, folios: [ folio_a, folio_b ], amount: 400, strategy: "outstanding_balance")

      expect(result).to be_success
      by_folio = result.allocations.index_by(&:booking_folio_id)
      expect(by_folio[folio_a.id].amount).to eq(300.to_d)
      expect(by_folio[folio_b.id].amount).to eq(100.to_d)
    end
  end

  describe "proportional strategy" do
    it "splits the amount proportionally to each folio's outstanding balance" do
      folio_a = folio_with_balance(300)
      folio_b = folio_with_balance(100)

      result = described_class.call(deposit: deposit, folios: [ folio_a, folio_b ], amount: 400, strategy: "proportional")

      expect(result).to be_success
      by_folio = result.allocations.index_by(&:booking_folio_id)
      expect(by_folio[folio_a.id].amount).to eq(300.to_d)
      expect(by_folio[folio_b.id].amount).to eq(100.to_d)
    end
  end

  it "rejects an unknown strategy" do
    folio_a = folio_with_balance(100)

    result = described_class.call(deposit: deposit, folios: [ folio_a ], amount: 100, strategy: "lottery")

    expect(result).not_to be_success
    expect(result.error).to include("Unknown allocation strategy")
  end

  it "rejects requests that exceed the available deposit amount" do
    folio_a = folio_with_balance(2_000)

    result = described_class.call(deposit: deposit, folios: [ folio_a ], amount: 1_500, strategy: "outstanding_balance")

    expect(result).not_to be_success
    expect(result.error).to include("exceeds")
  end

  it "requires at least one folio" do
    result = described_class.call(deposit: deposit, folios: [], amount: 100, strategy: "manual")

    expect(result).not_to be_success
    expect(result.error).to include("Select at least one folio")
  end
end
