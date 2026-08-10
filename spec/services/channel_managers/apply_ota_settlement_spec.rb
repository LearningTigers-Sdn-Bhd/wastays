# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ApplyOtaSettlement do
  let(:booking) { create(:booking) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:settlement) do
    create(:channel_settlement, hotel: booking.hotel, booking_source: source,
      gross_amount: 100, commission_amount: 10, expected_net_amount: 90,
      collection_by: "ota", channel_manager_reference: "ota-settlement-1")
  end

  it "allocates and posts one gross OTA credit without a PMS receipt" do
    result = described_class.call!(booking:, settlement:)

    expect(result).to be_success
    allocation = settlement.channel_settlement_allocations.find_by!(booking: booking)
    expect(allocation.booking_folio.payer_type).to eq("ota")
    transaction = allocation.booking_folio.folio_transactions.find_by!(operation_key: "ota_credit:settlement:#{settlement.id}:allocation:#{allocation.id}")
    expect(transaction).to have_attributes(transaction_type: "payment", amount: 100.to_d, category: "booking_payment")
    expect(transaction).to be_ota_collected_credit
    expect(transaction.metadata).to include(
      "channel_settlement_id" => settlement.id,
      "channel_settlement_allocation_id" => allocation.id,
      "booking_source_id" => source.id,
      "receipt_policy" => "none",
      "posting_source" => "ota_credit"
    )
    expect(transaction.receipt).to be_nil
    expect { described_class.call!(booking:, settlement:) }.not_to change(FolioTransaction, :count)
  end

  it "does not post for property or unknown collection" do
    %w[property unknown].each do |collection_by|
      non_ota = create(:channel_settlement, hotel: booking.hotel, booking_source: source,
        collection_by:, channel_manager_reference: "#{collection_by}-settlement")
      expect { described_class.call!(booking:, settlement: non_ota) }.not_to change(FolioTransaction, :count)
    end
  end

  it "does not fabricate a refund when a settlement is cancelled" do
    described_class.call!(booking:, settlement:)
    settlement.update!(status: "cancelled")

    expect { described_class.call!(booking:, settlement:) }.not_to change(FolioTransaction, :count)
    expect(settlement.channel_settlement_allocations.first.booking_folio.folio_transactions.payment.sum(:amount)).to eq(100.to_d)
  end


  it "allocates a group settlement by child total_amount and keeps a deterministic remainder" do
    group = create(:group_booking, hotel: booking.hotel)
    first = create(:booking, hotel: booking.hotel, group_booking: group, group_position: 1, total_amount: 100)
    last = create(:booking, hotel: booking.hotel, group_booking: group, group_position: 2, total_amount: 200)
    group_settlement = create(:channel_settlement, hotel: booking.hotel, booking_source: source,
      gross_amount: 100, commission_amount: 10, expected_net_amount: 90,
      collection_by: "ota", channel_manager_reference: "ota-group-settlement")

    result = described_class.call_many(bookings: [ last, first ], settlement: group_settlement)

    expect(result).to be_success
    allocations = group_settlement.channel_settlement_allocations.order(:booking_id)
    expect(allocations.order(:booking_id).pluck(:gross_amount)).to match_array([ 33.33.to_d, 66.67.to_d ])
    expect(allocations.order(:booking_id).pluck(:commission_amount)).to match_array([ 3.33.to_d, 6.67.to_d ])
    expect(allocations.sum(:gross_amount)).to eq(100.to_d)
    expect(allocations.sum(:commission_amount)).to eq(10.to_d)
    expect(FolioTransaction.where(booking_folio: allocations.map(&:booking_folio)).sum(:amount)).to eq(100.to_d)
  end

  it "does not create a credit for a cancelled group child" do
    group = create(:group_booking, hotel: booking.hotel)
    child = create(:booking, hotel: booking.hotel, group_booking: group, group_position: 1, status: "cancelled")
    group_settlement = create(:channel_settlement, hotel: booking.hotel, booking_source: source,
      gross_amount: 100, commission_amount: 10, expected_net_amount: 90,
      collection_by: "ota", channel_manager_reference: "ota-cancelled-child")

    expect {
      described_class.call_many(bookings: [ child ], settlement: group_settlement)
    }.not_to change(FolioTransaction, :count)
  end
end
