require "rails_helper"

RSpec.describe GroupDeposits::Receive do
  let(:group) { create(:group_booking) }
  let(:hotel) { group.hotel }

  it "records a received group deposit" do
    result = described_class.call(
      group_booking: group,
      amount: 1_000,
      currency: hotel.default_currency,
      payment_method: "bank_transfer",
      received_by: nil,
      external_reference: "REF-001"
    )

    expect(result).to be_success
    expect(result.deposit).to have_attributes(
      group_booking_id: group.id,
      hotel_id: hotel.id,
      amount: 1_000.to_d,
      status: "received",
      external_reference: "REF-001"
    )
    expect(result.deposit.received_at).to be_present
  end

  it "fails when required attributes are missing" do
    result = described_class.call(
      group_booking: group,
      amount: 1_000,
      currency: nil,
      payment_method: "bank_transfer"
    )

    expect(result).not_to be_success
    expect(result.error).to be_present
    expect(result.deposit).to be_nil
  end

  it "fails when the external reference is already used for the hotel" do
    create(:group_deposit, group_booking: group, hotel: hotel, external_reference: "REF-DUP")

    result = described_class.call(
      group_booking: group,
      amount: 500,
      currency: hotel.default_currency,
      payment_method: "bank_transfer",
      external_reference: "REF-DUP"
    )

    expect(result).not_to be_success
    expect(result.error).to include("External reference")
  end
end
