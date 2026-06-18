require "rails_helper"

RSpec.describe EInvoice::Submit, type: :service do
  describe ".call" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel) }
    let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }

    before do
      # Mock the credentials myinvois call
      allow(Rails.application.credentials).to receive(:myinvois).and_return(
        double(
          to_h: {
            tin: "C1234567890",
            brn: "202301012345",
            name: "Jesselton Pixel Sdn Bhd",
            phone: "+60111234567",
            email: "finance@wastays.com",
            city: "Kota Kinabalu",
            postal_code: "88000",
            state_code: "12",
            address: "123 Street"
          }
        )
      )

      # Mock document builder
      allow_any_instance_of(EInvoice::DocumentBuilder).to receive(:build).and_return({
        format: "JSON",
        document: "mock-doc",
        documentHash: "mock-hash",
        codeNumber: "INV-001"
      })

      # Stub MyInvois ClientFactory
      @mock_client = double("MyInvois::Client")
      allow(MyInvois::ClientFactory).to receive(:build).and_return(@mock_client)
    end

    context "when booking has no closed folio" do
      before { folio.update!(status: "open") }

      it "returns failure" do
        result = described_class.call(booking)
        expect(result[:success]).to be false
        expect(result[:error]).to include("does not have a closed folio")
      end
    end

    context "when successful submission" do
      before do
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "sub-123",
          "acceptedDocuments" => [
            { "uuid" => "uuid-123" }
          ]
        })
      end

      it "creates a new submission record" do
        expect {
          result = described_class.call(booking)
          expect(result[:success]).to be true
          expect(result[:submission].status).to eq("submitted")
        }.to change(EInvoiceSubmission, :count).by(1)
      end

      it "resets attributes when resubmitting a cancelled or rejected invoice" do
        existing = create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          status: "cancelled",
          uuid: "old-uuid",
          long_id: "old-long-id",
          cancelled_at: 1.day.ago,
          validated_at: 2.days.ago,
          raw_response: { old: "data" },
          error_details: { err: "yes" }
        )

        result = described_class.call(booking)
        expect(result[:success]).to be true
        submission = result[:submission]

        expect(submission.id).to eq(existing.id)
        expect(submission.status).to eq("submitted")
        expect(submission.uuid).to eq("uuid-123")
        expect(submission.cancelled_at).to be_nil
        expect(submission.validated_at).to be_nil
        expect(submission.raw_response).to eq({
          "submissionUid" => "sub-123",
          "acceptedDocuments" => [{ "uuid" => "uuid-123" }]
        })
        expect(submission.error_details).to eq({})
      end
    end
  end
end
