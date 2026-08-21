require "rails_helper"

RSpec.describe EInvoice::IssueAdjustment, type: :service do
  let(:hotel) { create(:hotel, tin: "C1234567890", ssm_number: "202301012345") }
  let!(:e_invoice_setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }
  let(:booking) do
    create(:booking, hotel: hotel, payment_status: "captured", total_amount: 500.0, fund_collector: "wastays", guest_city: "Kota Kinabalu", guest_country: "Malaysia", guest_tin: "IG12345678901")
  end
  let(:credentials_hash) do
    {
      tin: "C1234567890", brn: "202301012345", name: "Jesselton Pixel Sdn Bhd",
      phone: "+60111234567", email: "finance@wastays.com",
      city: "Kota Kinabalu", postal_code: "88000", state_code: "12",
      address: "123 Street"
    }
  end

  before do
    create(:booking_room, booking: booking, subtotal: 500.0)
    allow(Rails.application.credentials).to receive(:myinvois)
      .and_return(double(to_h: credentials_hash))
  end

  describe ".call" do
    context "when folio is not closed" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "open") }

      it "returns skipped" do
        result = described_class.call(booking)
        expect(result[:skipped]).to be true
        expect(result[:message]).to include("not closed")
      end
    end

    context "when no valid original e-invoice exists" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }

      it "returns skipped" do
        result = described_class.call(booking)
        expect(result[:skipped]).to be true
        expect(result[:message]).to include("No valid original e-invoice")
      end
    end

    context "when folio matches original invoice (no adjustment needed)" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
      let!(:original) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01", status: "valid",
          internal_id: "INV-001", uuid: "orig-uuid-123",
          raw_response: { "acceptedDocuments" => [ { "totalIncludingTax" => 500 } ] })
      end

      before do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 500.0)
      end

      it "returns skipped with no adjustment needed" do
        result = described_class.call(booking)
        expect(result[:skipped]).to be true
        expect(result[:message]).to include("No adjustment needed")
      end
    end

    context "when folio has extra charges (needs debit note)" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
      let!(:original) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01", status: "valid",
          internal_id: "INV-001", uuid: "orig-uuid-123",
          raw_response: { "acceptedDocuments" => [ { "totalIncludingTax" => 500 } ] })
      end

      before do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 580.0)

        @mock_client = double("MyInvois::Client")
        allow(MyInvois::ClientFactory).to receive(:build).and_return(@mock_client)
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "dn-sub-123",
          "acceptedDocuments" => [ { "uuid" => "dn-uuid-123" } ]
        })
      end

      it "issues a debit note (03) for the difference" do
        result = described_class.call(booking)
        expect(result[:success]).to be true

        submission = result[:submission]
        expect(submission.document_type).to eq("03")
        expect(submission.status).to eq("submitted")
        expect(submission.uuid).to eq("dn-uuid-123")
        expect(submission.original_invoice_internal_id).to eq("INV-001")
      end
    end

    context "when folio has less charges (needs credit note)" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
      let!(:original) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01", status: "valid",
          internal_id: "INV-001", uuid: "orig-uuid-123",
          raw_response: { "acceptedDocuments" => [ { "totalIncludingTax" => 500 } ] })
      end

      before do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 450.0)

        @mock_client = double("MyInvois::Client")
        allow(MyInvois::ClientFactory).to receive(:build).and_return(@mock_client)
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "cn-sub-123",
          "acceptedDocuments" => [ { "uuid" => "cn-uuid-123" } ]
        })
      end

      it "issues a credit note (02) for the difference" do
        result = described_class.call(booking)
        expect(result[:success]).to be true

        submission = result[:submission]
        expect(submission.document_type).to eq("02")
        expect(submission.status).to eq("submitted")
      end
    end
  end

  describe ".preview" do
    context "when folio matches the original invoice" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
      let!(:original) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01", status: "valid",
          internal_id: "INV-001", uuid: "orig-uuid-123",
          raw_response: { "acceptedDocuments" => [ { "totalIncludingTax" => 500 } ] })
      end

      before do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 500.0)
      end

      it "reports that no adjustment note is needed" do
        result = described_class.preview(booking)

        expect(result.needed?).to be false
        expect(result.message).to include("No adjustment note is needed")
      end
    end

    context "when folio differs from the original invoice" do
      let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
      let!(:original) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          document_type: "01", status: "valid",
          internal_id: "INV-001", uuid: "orig-uuid-123",
          raw_response: { "acceptedDocuments" => [ { "totalIncludingTax" => 500 } ] })
      end

      before do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 580.0)
      end

      it "reports that an adjustment note is needed" do
        result = described_class.preview(booking)

        expect(result.needed?).to be true
        expect(result.document_type).to eq("03")
        expect(result.message).to include("debit note")
      end
    end
  end
end
