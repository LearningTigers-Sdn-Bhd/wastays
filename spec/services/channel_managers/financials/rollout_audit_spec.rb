# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::RolloutAudit do
  describe ".call" do
    it "blocks a current snapshot when any folio transaction has already been posted" do
      hotel = create(:hotel)
      booking = create(:booking, hotel:, channel_manager_reference: "cm-posted-1")
      snapshot = create(:ota_financial_snapshot,
        hotel:, booking:, channel_manager_reference: booking.channel_manager_reference)
      create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:)
      folio = create(:booking_folio, hotel:, booking:)
      create(:folio_transaction, booking_folio: folio,
        transaction_code: create(:transaction_code, hotel:, kind: "charge", category: "accommodation"))

      result = described_class.call(hotel:)
      row = result.rows.find { |candidate| candidate[:booking_id] == booking.id }

      expect(row).to include(
        classification: :blocked_by_posted_history,
        posted_history: true,
        snapshot_id: snapshot.id,
        adjustment_proposal: {
          "amount" => "0.0", "currency" => snapshot.currency, "action" => "staff_approval_required"
        }
      )
      expect(result.counts[:blocked_by_posted_history]).to eq(1)
    end

    it "previews an unposted current snapshot as safe to reproject without changing records" do
      hotel = create(:hotel)
      booking = create(:booking, hotel:, channel_manager_reference: "cm-preview-1")
      snapshot = create(:ota_financial_snapshot,
        hotel:, booking:, channel_manager_reference: booking.channel_manager_reference)
      component = create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:)
      timestamps = [ booking.reload.updated_at, snapshot.reload.updated_at, component.reload.updated_at ]
      record_counts = [ FolioTransaction.count, FolioForecastedCharge.count, OtaFinancialSnapshot.count ]

      result = described_class.call(hotel:)
      row = result.rows.find { |candidate| candidate[:booking_id] == booking.id }

      expect(row).to include(
        classification: :safe_to_reproject,
        posted_history: false,
        component_count: 1,
        projected_component_count: 0
      )
      expect(result.counts[:safe_to_reproject]).to eq(1)
      expect([ booking.reload.updated_at, snapshot.reload.updated_at, component.reload.updated_at ]).to eq(timestamps)
      expect([ FolioTransaction.count, FolioForecastedCharge.count, OtaFinancialSnapshot.count ]).to eq(record_counts)
    end

    it "returns complete category counts and only an operational data allowlist" do
      hotel = create(:hotel)
      legacy = create(:booking, hotel:, channel_manager_reference: "cm-legacy-1",
        guest_name: "Secret Guest", guest_email: "secret@example.test", guest_phone: "+60123456789")
      reviewed = create(:booking, hotel:, channel_manager_reference: "cm-review-1")
      create(:ota_financial_snapshot, hotel:, booking: reviewed,
        channel_manager_reference: reviewed.channel_manager_reference,
        reconciliation_status: "rate_review_required")

      result = described_class.call(hotel:)

      expect(result.counts.keys).to eq(described_class::CATEGORIES)
      expect(result.counts).to include(legacy_missing_snapshot: 1, review_required: 1)
      expect(result.rows.find { |row| row[:booking_id] == legacy.id }[:classification]).to eq(:legacy_missing_snapshot)
      expect(result.rows.flat_map(&:keys).uniq).to contain_exactly(
        :classification, :booking_id, :group_booking_id, :snapshot_id,
        :channel_manager_reference, :provider, :reconciliation_status,
        :component_count, :projected_component_count, :posted_history, :adjustment_proposal
      )
      expect(result.rows.to_s).not_to include("Secret Guest", "secret@example.test", "+60123456789")
    end
  end
end
