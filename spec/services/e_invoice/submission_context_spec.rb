# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::SubmissionContext do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, payment_status: "captured") }

  # WAStays is under the RM1m threshold and files nothing as its own supplier.
  # Each hotel files under its own LHDN registration.
  context "when the hotel is set up to file" do
    let!(:setting) { create(:e_invoice_setting, hotel: hotel, hotel_tin: "C9988776655") }

    it "files as the hotel, in taxpayer mode" do
      context = described_class.for(booking)

      expect(context.submission_mode).to eq("taxpayer")
      expect(context.supplier_tin).to eq("C9988776655")
      expect(context.supplier_name).to eq(setting.supplier_name)
      expect(context.represented_taxpayer_tin).to be_nil
    end

    # Who took the guest's money decides payouts, not who issues the invoice.
    it "files as the hotel even when the hotel collected the payment directly" do
      booking.update!(fund_collector: "hotel")

      expect(described_class.for(booking).submission_mode).to eq("taxpayer")
    end

    it "files as the hotel even when the collector was never established" do
      booking.update!(fund_collector: "unknown")

      expect { described_class.for(booking) }.not_to raise_error
    end
  end

  context "when the hotel has not connected its LHDN account" do
    let!(:setting) { create(:e_invoice_setting, :not_connected, hotel: hotel) }

    it "refuses with something the hotel can act on" do
      expect { described_class.for(booking) }
        .to raise_error(described_class::ConfigurationError, /has not connected its LHDN account/)
    end
  end

  context "when the hotel has no e-invoice settings at all" do
    it "refuses rather than filing under someone else's identity" do
      expect { described_class.for(booking) }
        .to raise_error(described_class::ConfigurationError, /have not been set up/)
    end
  end

  # Kept for when WAStays crosses the threshold and registers.
  context "when filing on the hotel's behalf as an intermediary" do
    let!(:setting) { create(:e_invoice_setting, :intermediary_ready, hotel: hotel, hotel_tin: "C9988776655") }

    it "names the hotel as the represented taxpayer" do
      context = described_class.for(booking, document_scenario: "hotel_intermediary_guest_invoice")

      expect(context.submission_mode).to eq("intermediary")
      expect(context.represented_taxpayer_tin).to eq("C9988776655")
    end
  end
end
