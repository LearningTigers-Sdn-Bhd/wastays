require "rails_helper"

RSpec.describe EInvoiceSubmission, type: :model do
  describe "#document_scenario_label" do
    it "maps scenario label" do
      submission = build(:e_invoice_submission, document_scenario: "commission_invoice")

      expect(submission.document_scenario_label).to eq("WAStays service fee invoice")
    end
  end

  describe "#status_label" do
    it "maps friendly status labels" do
      submission = build(:e_invoice_submission, status: "submitted")

      expect(submission.status_label).to eq("Sent")
    end
  end

  describe "#cancellable?" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel) }
    let(:original) do
      create(:e_invoice_submission, hotel: hotel, booking: booking,
        status: "valid", validated_at: 1.hour.ago, internal_id: "INV-001", uuid: "LHDN-UUID-1")
    end

    it "is cancellable when nothing references it" do
      expect(original.cancellable?).to be(true)
    end

    # A blank uuid means there is nothing at LHDN to cancel - offering the
    # button anyway calls MyInvois::Client#cancel_document with an empty
    # UUID in the URL, which LHDN answers with a 404 rather than something
    # actionable.
    it "is not cancellable without a uuid" do
      original.update_columns(uuid: nil)

      expect(original.cancellable?).to be(false)
    end

    # Confirmed live against LHDN preprod: cancelling a document another
    # active document refers to is rejected with a 400
    # ("The document cannot be cancelled or requested for rejection").
    it "is not cancellable while an active credit or debit note references it" do
      create(:e_invoice_submission, hotel: hotel, booking: booking,
        status: "valid", document_type: "02", original_invoice_internal_id: "INV-001")

      expect(original.reload.cancellable?).to be(false)
      expect(original.referenced_by_active_adjustment?).to be(true)
      expect(original.cancellation_window_closed?).to be(false)
    end

    it "is cancellable again once the referencing adjustment is cancelled" do
      adjustment = create(:e_invoice_submission, hotel: hotel, booking: booking,
        status: "valid", document_type: "02", original_invoice_internal_id: "INV-001")
      adjustment.update!(status: "cancelled")

      expect(original.reload.cancellable?).to be(true)
    end
  end

  describe "#validation_url" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel) }
    let(:submission) do
      EInvoiceSubmission.new(
        hotel: hotel,
        booking: booking,
        uuid: "12345-uuid",
        long_id: "67890-longid"
      )
    end

    context "when credentials environment is sandbox" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:myinvois, :environment).and_return("sandbox")
      end

      it "returns the preprod validation url" do
        expect(submission.validation_url).to eq("https://preprod.myinvois.hasil.gov.my/12345-uuid/share/67890-longid")
      end
    end

    context "when credentials environment is production" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:myinvois, :environment).and_return("production")
      end

      it "returns the production validation url" do
        expect(submission.validation_url).to eq("https://myinvois.hasil.gov.my/12345-uuid/share/67890-longid")
      end
    end
  end
end
