# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ReconcileSettlementJob, type: :job do
  let(:hotel) { create(:hotel) }
  let(:source) { create(:booking_source, key: "retry_ota", kind: "ota") }
  let(:booking) { create(:booking, hotel:, channel_manager_reference: "channel-booking-1") }
  let(:settlement_data) do
    {
      provider: "channex",
      booking_source_key: source.key,
      channel_manager_reference: booking.channel_manager_reference,
      revision_id: "2",
      collection_by: "ota",
      settlement_method: "bank_transfer",
      status: "awaiting_ota_settlement",
      currency: hotel.default_currency,
      gross_amount: 100,
      commission_amount: 10,
      expected_net_amount: 90,
      metadata: { source_resolution: "resolved" }
    }
  end

  it "persists and idempotently applies a delayed settlement" do
    expect { described_class.new.perform(hotel.id, settlement_data) }
      .to change(ChannelSettlement, :count).by(1)
      .and change(FolioTransaction, :count).by(1)

    expect { described_class.new.perform(hotel.id, settlement_data) }
      .not_to change(FolioTransaction, :count)
  end

  it "marks a persisted settlement for attention when application fails" do
    settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: booking.channel_manager_reference,
      latest_revision_id: "1"
    )
    failed_result = double(success?: false, error: "Folio is closed")
    allow(ChannelManagers::ApplyOtaSettlement).to receive(:call).and_return(failed_result)

    expect { described_class.new.perform(hotel.id, settlement_data) }
      .to raise_error(described_class::ReconciliationError, "Folio is closed")

    expect(settlement.reload).to be_needs_attention
    expect(settlement.metadata).to include("reconciliation_error" => "Folio is closed")
  end

  it "clears the operator warning after a later retry succeeds" do
    settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: booking.channel_manager_reference,
      latest_revision_id: "2",
      status: "needs_attention",
      metadata: {
        "reconciliation_original_status" => "awaiting_ota_settlement",
        "reconciliation_error" => "Temporary failure"
      }
    )

    described_class.new.perform(hotel.id, settlement_data)

    expect(settlement.reload).to be_awaiting_ota_settlement
    expect(settlement.metadata).not_to include("reconciliation_error", "reconciliation_original_status")
  end

  it "raises a retryable error while an OTA source remains unresolved" do
    unresolved = settlement_data.merge(booking_source_key: "missing_ota")

    expect { described_class.new.perform(hotel.id, unresolved) }
      .to raise_error(described_class::ReconciliationError, /booking source is unknown/)
  end
end
