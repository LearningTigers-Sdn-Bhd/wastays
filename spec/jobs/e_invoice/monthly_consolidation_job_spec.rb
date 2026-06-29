require "rails_helper"

RSpec.describe EInvoice::MonthlyConsolidationJob, type: :job do
  let(:hotel) { create(:hotel) }
  let!(:e_invoice_setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }
  let(:credentials_hash) do
    {
      tin: "C1234567890", brn: "202301012345", name: "Jesselton Pixel Sdn Bhd",
      phone: "+60111234567", email: "finance@wastays.com",
      city: "Kota Kinabalu", postal_code: "88000", state_code: "12",
      address: "123 Street"
    }
  end

  before do
    allow(Rails.application.credentials).to receive(:myinvois)
      .and_return(double(to_h: credentials_hash))
  end

  describe "#perform" do
    let(:last_month) { Date.current.prev_month.beginning_of_month }
    let(:mid_last_month) { last_month + 10.days }
    # Reference date within the 7-day window after month end
    let(:within_window_date) { last_month.end_of_month + 3.days }

    let!(:qualifying_booking) do
      b = create(:booking, hotel: hotel, payment_status: "captured",
        total_amount: 300.0)
      create(:booking_room, booking: b, subtotal: 300.0, quantity: 1)
      b
    end

    let!(:qualifying_submission) do
      create(:e_invoice_submission,
        hotel: hotel, booking: qualifying_booking,
        document_scenario: "guest_invoice",
        status: "pending", consolidated: true,
        requested_by_guest: false,
        payment_concluded_at: mid_last_month)
    end

    before do
      @mock_client = double("MyInvois::Client")
      allow(MyInvois::ClientFactory).to receive(:build).and_return(@mock_client)
    end

    context "when submission is accepted" do
      before do
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "batch-sub-123",
          "acceptedDocuments" => [ { "uuid" => "batch-uuid-123" } ]
        })
      end

      it "updates qualifying submissions to submitted status" do
        described_class.perform_now(within_window_date)

        qualifying_submission.reload
        expect(qualifying_submission.status).to eq("submitted")
        expect(qualifying_submission.uuid).to eq("batch-uuid-123")
        expect(qualifying_submission.submission_uid).to eq("batch-sub-123")
        expect(qualifying_submission.consolidation_batch_id).to be_present
      end
    end

    context "when submission is rejected" do
      before do
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "batch-sub-fail",
          "rejectedDocuments" => [ {
            "error" => { "details" => [ { "message" => "Invalid format" } ] }
          } ]
        })
      end

      it "updates qualifying submissions to invalid status" do
        described_class.perform_now(within_window_date)

        qualifying_submission.reload
        expect(qualifying_submission.status).to eq("invalid")
        expect(qualifying_submission.error_details["messages"]).to include("Invalid format")
      end
    end

    context "when no qualifying submissions exist" do
      before do
        qualifying_submission.update!(consolidated: false)
        allow(@mock_client).to receive(:submit_documents)
      end

      it "does not call submit_documents" do
        described_class.perform_now(within_window_date)
        expect(@mock_client).not_to have_received(:submit_documents)
      end
    end

    context "excludes non-qualifying submissions" do
      before do
        qualifying_submission.update!(status: "cancelled")
      end

      let!(:already_submitted) do
        create(:e_invoice_submission,
          hotel: hotel, booking: qualifying_booking,
          document_scenario: "guest_invoice",
          status: "submitted", consolidated: true,
          payment_concluded_at: mid_last_month)
      end

      let!(:not_consolidated) do
        other = create(:booking, hotel: hotel, payment_status: "captured",
          total_amount: 200.0)
        create(:booking_room, booking: other, subtotal: 200.0, quantity: 1)
        create(:e_invoice_submission,
          hotel: hotel, booking: other,
          document_scenario: "guest_invoice",
          status: "pending", consolidated: false,
          payment_concluded_at: mid_last_month)
      end

      it "only processes qualifying pending consolidated submissions" do
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "batch-sub-clean",
          "acceptedDocuments" => [ { "uuid" => "batch-clean-uuid" } ]
        })

        described_class.perform_now(within_window_date)

        already_submitted.reload
        expect(already_submitted.uuid).to be_nil
      end
    end

    context "excludes guest-requested submissions" do
      before do
        qualifying_submission.update!(requested_by_guest: true)
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "batch-sub-clean",
          "acceptedDocuments" => [ { "uuid" => "batch-clean-uuid" } ]
        })
      end

      it "does not include guest-requested submissions in consolidation" do
        described_class.perform_now(within_window_date)

        qualifying_submission.reload
        expect(qualifying_submission.status).to eq("pending")
        expect(qualifying_submission.uuid).to be_nil
      end
    end

    context "excludes high-value bookings (>= RM10,000)" do
      let!(:high_value_booking) do
        b = create(:booking, hotel: hotel, payment_status: "captured",
          total_amount: 15_000.0)
        create(:booking_room, booking: b, subtotal: 15_000.0, quantity: 1)
        b
      end

      let!(:high_value_submission) do
        create(:e_invoice_submission,
          hotel: hotel, booking: high_value_booking,
          document_scenario: "guest_invoice",
          status: "pending", consolidated: true,
          requested_by_guest: false,
          payment_concluded_at: mid_last_month)
      end

      before do
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "batch-sub-clean",
          "acceptedDocuments" => [ { "uuid" => "batch-clean-uuid" } ]
        })
      end

      it "does not include high-value bookings in consolidation" do
        described_class.perform_now(within_window_date)

        high_value_submission.reload
        expect(high_value_submission.status).to eq("pending")
        expect(high_value_submission.uuid).to be_nil

        qualifying_submission.reload
        expect(qualifying_submission.status).to eq("submitted")
      end
    end

    context "excludes submissions outside the 7-day window" do
      before do
        # Try to run 8 days after month end
        run_date = last_month.end_of_month + 8.days
        allow(@mock_client).to receive(:submit_documents)
        described_class.perform_now(run_date)
      end

      it "does not process submissions outside the consolidation window" do
        expect(@mock_client).not_to have_received(:submit_documents)
      end
    end

    context "allows runs within the 7-day window" do
      before do
        # Run on the 7th day after month end
        run_date = last_month.end_of_month + 7.days
        allow(@mock_client).to receive(:submit_documents).and_return({
          "submissionUid" => "batch-sub-123",
          "acceptedDocuments" => [ { "uuid" => "batch-uuid-123" } ]
        })
        described_class.perform_now(run_date)
      end

      it "processes submissions within the 7-day window" do
        qualifying_submission.reload
        expect(qualifying_submission.status).to eq("submitted")
      end
    end

    context "processes hotel-direct (hotel_intermediary_guest_invoice) submissions in a separate batch" do
      let!(:hotel_direct_booking) do
        b = create(:booking, :direct_hotel_payment, hotel: hotel,
          payment_status: "captured", total_amount: 500.0)
        create(:booking_room, booking: b, subtotal: 500.0, quantity: 1)
        b
      end

      let!(:hotel_direct_submission) do
        create(:e_invoice_submission,
          hotel: hotel, booking: hotel_direct_booking,
          document_scenario: "hotel_intermediary_guest_invoice",
          status: "pending", consolidated: true,
          requested_by_guest: false,
          payment_concluded_at: mid_last_month)
      end

      before do
        hotel.e_invoice_setting.update!(
          intermediary_enabled: true,
          supplier_msic_code: "55101",
          supplier_business_description: "Hotel accommodation services",
          supplier_address_line1: "1 Jalan Hotel",
          supplier_city: "Kota Kinabalu",
          supplier_postal_code: "88000",
          supplier_state_code: "12",
          supplier_contact_phone: "+6088123456",
          supplier_contact_email: "finance@hotel.test"
        )
        allow(@mock_client).to receive(:submit_documents).and_return(
          {
            "submissionUid" => "batch-sub-123",
            "acceptedDocuments" => [ { "uuid" => "batch-uuid-123" } ]
          },
          {
            "submissionUid" => "batch-sub-456",
            "acceptedDocuments" => [ { "uuid" => "batch-uuid-456" } ]
          }
        )
      end

      it "submits hotel-direct low-value records instead of leaving them pending forever" do
        described_class.perform_now(within_window_date)

        hotel_direct_submission.reload
        expect(hotel_direct_submission.status).to eq("submitted")
        expect(hotel_direct_submission.uuid).to be_present

        qualifying_submission.reload
        expect(qualifying_submission.status).to eq("submitted")
      end
    end

    context "when both taxpayer and intermediary consolidated batches exist" do
      let!(:hotel_direct_booking) do
        b = create(:booking, :direct_hotel_payment, hotel: hotel,
          payment_status: "captured", total_amount: 500.0)
        create(:booking_room, booking: b, subtotal: 500.0, quantity: 1)
        b
      end

      let!(:hotel_direct_submission) do
        create(:e_invoice_submission,
          hotel: hotel, booking: hotel_direct_booking,
          document_scenario: "hotel_intermediary_guest_invoice",
          submission_mode: "intermediary",
          fund_collector: "hotel",
          status: "pending", consolidated: true,
          requested_by_guest: false,
          payment_concluded_at: mid_last_month)
      end

      before do
        hotel.e_invoice_setting.update!(
          intermediary_enabled: true,
          supplier_msic_code: "55101",
          supplier_business_description: "Hotel accommodation services",
          supplier_address_line1: "1 Jalan Hotel",
          supplier_city: "Kota Kinabalu",
          supplier_postal_code: "88000",
          supplier_state_code: "12",
          supplier_contact_phone: "+6088123456",
          supplier_contact_email: "finance@hotel.test"
        )

        allow(@mock_client).to receive(:submit_documents).and_return(
          {
            "submissionUid" => "batch-sub-123",
            "acceptedDocuments" => [ { "uuid" => "batch-uuid-123" } ]
          },
          {
            "submissionUid" => "batch-sub-456",
            "acceptedDocuments" => [ { "uuid" => "batch-uuid-456" } ]
          }
        )
      end

      it "builds one taxpayer client and one intermediary client" do
        expect(MyInvois::ClientFactory).to receive(:build).with(
          mode: :taxpayer, represented_taxpayer_tin: nil
        ).and_return(@mock_client)

        expect(MyInvois::ClientFactory).to receive(:build).with(
          mode: :intermediary, represented_taxpayer_tin: hotel.e_invoice_setting.hotel_tin
        ).and_return(@mock_client)

        described_class.perform_now(within_window_date)
      end
    end
  end
end
