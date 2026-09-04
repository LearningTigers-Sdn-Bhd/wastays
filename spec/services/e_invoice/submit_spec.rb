require "rails_helper"

RSpec.describe EInvoice::Submit, type: :service do
  describe ".call" do
    let(:hotel) { create(:hotel, tin: "C9988776655", ssm_number: "202399887766") }
    let!(:e_invoice_setting) do
      create(:e_invoice_setting, hotel: hotel)
    end
    let(:booking) do
      create(
        :booking,
        hotel: hotel,
        booking_quote: nil,
        payment_status: "captured",
        guest_home_address: "12 Jalan Ampang",
        guest_city: "Kuala Lumpur",
        guest_state_code: "14",
        guest_address_country: "Malaysia"
      )
    end
    let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }
    let!(:booking_room) { create(:booking_room, booking: booking, subtotal: 200.0) }

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

    context "when booking payment has not concluded" do
      let(:booking) { create(:booking, hotel: hotel, booking_quote: nil, payment_status: "pending") }
      let!(:folio) { create(:booking_folio, booking: booking, status: "open") }

      it "returns failure" do
        result = described_class.call(booking)
        expect(result[:success]).to be false
        expect(result[:error]).to include("payment has not concluded")
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
          supplier_name: hotel.name,
          supplier_tin: "C9988776655",
          represented_taxpayer_tin: nil
        )
        expect(result[:submission].buyer_snapshot).to include(
          "name" => booking.guest_name,
          "contact_email" => booking.guest_email,
          "contact_phone" => booking.guest_phone
        )
        expect(result[:submission].buyer_snapshot.dig("billing_address", "city")).to eq("Kuala Lumpur")
      end

      it "preserves a pending submission buyer snapshot during an automatic retry" do
        original_snapshot = EInvoice::BuyerSnapshot.capture(booking)
        submission = create(:e_invoice_submission,
          hotel:,
          booking:,
          status: "pending",
          buyer_snapshot: original_snapshot)
        booking.update!(guest_name: "Changed Guest", guest_home_address: "Changed address")

        result = described_class.call(submission)

        expect(result[:success]).to be(true)
        expect(result[:submission].buyer_snapshot).to eq(original_snapshot)
      end

      it "recaptures buyer details when an invalid submission is explicitly retried" do
        submission = create(:e_invoice_submission,
          hotel:,
          booking:,
          status: "invalid",
          buyer_snapshot: { "name" => "Old Guest", "billing_address" => { "city" => "Old City" } })
        booking.update!(guest_name: "Corrected Guest", guest_city: "Kuching", guest_state_code: "13")

        result = described_class.call(submission)

        expect(result[:success]).to be(true)
        expect(result[:submission].buyer_snapshot["name"]).to eq("Corrected Guest")
        expect(result[:submission].buyer_snapshot.dig("billing_address", "city")).to eq("Kuching")
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
          "acceptedDocuments" => [ { "uuid" => "uuid-123" } ]
        })
        expect(submission.error_details).to eq({})
      end
    end

    context "when the hotel collected payment directly" do
      let(:booking) do
        create(
          :booking,
          :direct_hotel_payment,
          hotel: hotel,
          booking_quote: nil,
          payment_status: "captured",
          guest_home_address: "12 Jalan Ampang",
          guest_city: "Kuala Lumpur",
          guest_state_code: "14",
          guest_address_country: "Malaysia"
        )
      end

      before do
        e_invoice_setting.update!(intermediary_enabled: true)
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
          represented_taxpayer_tin: "C9988776655",
          setting: e_invoice_setting
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
      let(:booking) { create(:booking, hotel: hotel, booking_quote: nil, status: "completed", fund_collector: "wastays", net_amount: 320.0, payment_status: "captured") }
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
        e_invoice_setting.update!(intermediary_enabled: true)
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

      it "uses self-billed document type and taxpayer submission mode, authenticated as WAStays" do
        result = described_class.call(submission)

        # WAStays self-bills the hotel here, so WAStays - not the hotel -
        # must be the authenticated party (confirmed live against LHDN
        # preprod: it rejects the submission otherwise). `setting: nil`
        # sends MyInvois::Client down WAStays' own-credentials path.
        expect(MyInvois::ClientFactory).to have_received(:build).with(
          mode: :taxpayer,
          represented_taxpayer_tin: nil,
          setting: nil
        )
        expect(result[:submission]).to have_attributes(
          document_scenario: "payout_self_billed_invoice",
          document_type: "11",
          submission_mode: "taxpayer",
          supplier_tin: "C9988776655"
        )
      end
    end

    context "when LHDN is briefly unavailable" do
      before do
        allow(@mock_client).to receive(:submit_documents).and_raise(
          MyInvois::Client::ApiError.new("Service unavailable", code: "503")
        )
      end

      # The job's retry_on can only back off if the error escapes the service.
      # Swallowing it here would strand the document as invalid on a blip.
      it "re-raises so the job retries, and writes off nothing" do
        expect { described_class.call(booking) }.to raise_error(MyInvois::Client::ApiError)

        expect(booking.e_invoice_submissions.where(status: "invalid")).to be_empty
      end

      it "still writes off a document LHDN actually rejected" do
        allow(@mock_client).to receive(:submit_documents).and_raise(
          MyInvois::Client::ApiError.new("Buyer TIN invalid", code: "400")
        )

        result = described_class.call(booking)

        expect(result[:success]).to be false
        expect(result[:submission].status).to eq("invalid")
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

    context "when document building raises a runtime error" do
      before do
        allow_any_instance_of(EInvoice::DocumentBuilder).to receive(:build)
          .and_raise(ArgumentError, "Booking guest city must map to a valid Malaysia state code")
      end

      it "marks the submission invalid instead of leaving it pending" do
        result = described_class.call(booking)

        expect(result[:success]).to be false
        expect(result[:submission].status).to eq("invalid")
        expect(result[:submission].error_details).to include(
          "message" => "Booking guest city must map to a valid Malaysia state code",
          "exception_class" => "ArgumentError"
        )
      end
    end
  end
end
