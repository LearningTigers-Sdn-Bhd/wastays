# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::PersistSettlement do
  let(:hotel) { create(:hotel) }
  let(:source) { BookingSource.find_or_initialize_by(key: "booking_com").tap { |record| record.update!(kind: "ota", active: true) } }

  def settlement_data(revision_id: "10", **overrides)
    {
      provider: "channex",
      booking_source_key: source.key,
      channel_manager_reference: "cm-reference-1",
      external_reference: "ota-reference-1",
      revision_id: revision_id,
      collection_by: "ota",
      settlement_method: "bank_transfer",
      currency: "MYR",
      gross_amount: 100,
      commission_amount: 10,
      expected_net_amount: 90,
      status: "awaiting_ota_settlement",
      virtual_card: {},
      metadata: {
        "provider_status" => "new",
        "payment_collect" => "ota",
        "payment_type" => "bank_transfer",
        "card_number" => "must-not-persist"
      }
    }.merge(overrides)
  end

  it "creates an OTA settlement without creating folio transactions or receipts" do
    expect {
      @result = described_class.call(hotel:, settlement_data: settlement_data)
    }.to change(ChannelSettlement, :count).by(1)
    expect(FolioTransaction.count).to eq(0)

    settlement = @result.settlement
    expect(@result).to be_success
    expect(@result).to be_created
    expect(settlement).to have_attributes(
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: "cm-reference-1",
      latest_revision_id: "10",
      gross_amount: 100.to_d,
      commission_amount: 10.to_d,
      expected_net_amount: 90.to_d
    )
    expect(settlement.metadata).to eq(
      "provider_status" => "new",
      "payment_collect" => "ota",
      "payment_type" => "bank_transfer"
    )
  end

  it "is idempotent and ignores duplicate or older revisions" do
    first = described_class.call(hotel:, settlement_data: settlement_data(revision_id: "10"))
    duplicate = described_class.call(hotel:, settlement_data: settlement_data(revision_id: "10", gross_amount: 999, commission_amount: 1))
    older = described_class.call(hotel:, settlement_data: settlement_data(revision_id: "9", gross_amount: 80, commission_amount: 8))

    expect(first).to be_created
    expect(duplicate).to be_ignored
    expect(older).to be_ignored
    expect(ChannelSettlement.count).to eq(1)
    expect(first.settlement.reload).to have_attributes(
      latest_revision_id: "10",
      gross_amount: 100.to_d,
      commission_amount: 10.to_d
    )
  end

  it "updates the same settlement identity for a newer revision" do
    described_class.call(hotel:, settlement_data: settlement_data(revision_id: "10"))

    result = described_class.call(
      hotel:,
      settlement_data: settlement_data(
        revision_id: "11",
        gross_amount: 150,
        commission_amount: 15,
        expected_net_amount: 135,
        status: "ready_to_charge"
      )
    )

    expect(result).to be_updated
    expect(ChannelSettlement.count).to eq(1)
    expect(result.settlement.reload).to have_attributes(
      latest_revision_id: "11",
      gross_amount: 150.to_d,
      commission_amount: 15.to_d,
      expected_net_amount: 135.to_d,
      status: "ready_to_charge"
    )
  end

  it "does not persist unknown, inactive, or non-OTA sources" do
    unknown = described_class.call(hotel:, settlement_data: settlement_data(booking_source_key: "missing_source"))
    source.update!(active: false)
    inactive = described_class.call(hotel:, settlement_data: settlement_data)
    source.update!(active: true, kind: "manual")
    non_ota = described_class.call(hotel:, settlement_data: settlement_data)

    expect([ unknown, inactive, non_ota ]).to all(be_needs_attention)
    expect(ChannelSettlement.count).to eq(0)
  end
end
