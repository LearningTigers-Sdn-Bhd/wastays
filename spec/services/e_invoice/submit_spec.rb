require "rails_helper"

RSpec.describe EInvoice::Submit, type: :service do
  describe ".call" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel, booking_quote: nil) }
    let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
    let!(:booking_room) { create(:booking_room, booking: booking, subtotal: 200.0, quantity: 1) }

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

    context "when booking has no hotel" do
      let(:booking) do
        Booking.new(
          hotel: nil,
          booking_quote: nil,
          guest_name: "Guest",
          guest_email: "guest@example.com",
          guest_phone: "+60123456789",
          total_amount: 200.0,
          currency: "MYR",
          status: "confirmed",
          payment_status: "pending",
          adults: 2,
          check_in: Time.current,
          check_out: 1.day.from_now,
          confirmation_token: "NOHOTL"
        )
      end
      let!(:folio) { nil }
      let!(:booking_room) { nil }

      it "raises an argument error" do
        expect { described_class.call(booking) }
          .to raise_error(ArgumentError, "Booking must have an associated hotel")
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

      it "stores the supplier/auth snapshot on the submission" do
        result = described_class.call(booking)

        expect(result[:submission]).to have_attributes(
          document_scenario: "guest_invoice",
          submission_mode: "taxpayer",
          fund_collector: "wastays",
          supplier_name: "Jesselton Pixel Sdn Bhd",
          supplier_tin: "C1234567890",
          represented_taxpayer_tin: nil
        )
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

    context "when the hotel collected payment directly" do
      let(:booking) { create(:booking, :direct_hotel_payment, hotel: hotel, booking_quote: nil) }

      before do
        create(:e_invoice_setting, :intermediary_ready, hotel: hotel, hotel_tin: "C9988776655", hotel_brn: "202399887766")
        allow(MyInvois::ClientFactory).to receive(:build).and_return(@mock_client)
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "sub-123",
          "acceptedDocuments" => [
            { "uuid" => "uuid-123" }
          ]
        })
      end

      it "authenticates in intermediary mode and snapshots the represented hotel" do
        result = described_class.call(booking)

        expect(MyInvois::ClientFactory).to have_received(:build).with(
          mode: :intermediary,
          represented_taxpayer_tin: "C9988776655"
        )
        expect(result[:submission]).to have_attributes(
          document_scenario: "hotel_intermediary_guest_invoice",
          submission_mode: "intermediary",
          fund_collector: "hotel",
          supplier_name: hotel.name,
          supplier_tin: "C9988776655",
          represented_taxpayer_tin: "C9988776655"
        )
      end

      it "reuses explicit submission record instead of looking up by booking uniqueness" do
        submission = create(:e_invoice_submission, booking: booking, hotel: hotel, document_scenario: "hotel_intermediary_guest_invoice")

        result = described_class.call(submission)

        expect(result[:success]).to be true
        expect(result[:submission].id).to eq(submission.id)
      end
    end

    context "when submitting payout self-billed invoice" do
      let(:booking) { create(:booking, hotel: hotel, booking_quote: nil, status: "completed", fund_collector: "wastays", net_amount: 320.0) }
      let!(:submission) do
        create(:e_invoice_submission,
          hotel: hotel,
          booking: booking,
          document_scenario: "payout_self_billed_invoice",
          document_type: "11",
          submission_mode: "taxpayer",
          fund_collector: "wastays")
      end

      before do
        create(:e_invoice_setting, :intermediary_ready, hotel: hotel, hotel_tin: "C9988776655", hotel_brn: "202399887766")
        allow_any_instance_of(EInvoice::PayoutSelfBilledDocumentBuilder).to receive(:build).and_return({
          format: "JSON",
          document: "mock-doc",
          documentHash: "mock-hash",
          codeNumber: "SBI-001"
        })
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "sub-123",
          "acceptedDocuments" => [
            { "uuid" => "uuid-123" }
          ]
        })
      end

      it "uses self-billed document type and taxpayer submission mode" do
        result = described_class.call(submission)

        expect(MyInvois::ClientFactory).to have_received(:build).with(
          mode: :taxpayer,
          represented_taxpayer_tin: nil
        )
        expect(result[:submission]).to have_attributes(
          document_scenario: "payout_self_billed_invoice",
          document_type: "11",
          submission_mode: "taxpayer",
          supplier_tin: "C9988776655"
        )
      end
    end

    context "when MyInvois returns huge error payload" do
      before do
        allow(@mock_client).to receive(:submit_documents).and_raise(
          MyInvois::Client::ApiError.new("Submission failed", code: "400", body: { raw: "x" * 1000 })
        )
      end

      it "truncates stored error body" do
        result = described_class.call(booking)

        expect(result[:success]).to be false
        expect(result[:submission].status).to eq("invalid")
        expect(result[:submission].error_details["body"].length).to be <= 500
      end
    end
  end
end
