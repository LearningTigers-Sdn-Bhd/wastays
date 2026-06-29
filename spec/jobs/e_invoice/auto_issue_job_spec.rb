require "rails_helper"

RSpec.describe EInvoice::AutoIssueJob, type: :job do
  let(:hotel) { create(:hotel) }
  let!(:e_invoice_setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }

  before do
    allow(Rails.application.credentials).to receive(:myinvois)
      .and_return(double(to_h: {
        tin: "C1234567890", brn: "202301012345", name: "Jesselton Pixel Sdn Bhd",
        phone: "+60111234567", email: "finance@wastays.com",
        city: "Kota Kinabalu", postal_code: "88000", state_code: "12", address: "123"
      }))
  end

  describe "#perform" do
    context "when hotel e-invoicing is disabled" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 500.0)
      end

      before { e_invoice_setting.update!(enabled: false) }

      it "does nothing" do
        expect {
          described_class.perform_now(booking.id)
        }.not_to change(EInvoiceSubmission, :count)
      end
    end

    context "when booking is high value (>= RM10,000)" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 15_000.0)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 15_000.0, quantity: 1)
        allow(EInvoice::SubmitJob).to receive(:perform_later)
      end

      it "creates and submits an individual e-invoice" do
        expect {
          described_class.perform_now(booking.id)
        }.to change(EInvoiceSubmission, :count).by(1)

        submission = EInvoiceSubmission.last
        expect(submission.document_type).to eq("01")
        expect(submission.status).to eq("pending")
        expect(submission.requested_by_guest).to be false
        expect(submission.consolidated).to be false
        expect(EInvoice::SubmitJob).to have_received(:perform_later).with(submission.id)
      end
    end

    context "when booking is exactly RM10,000" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 10_000.0)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 10_000.0, quantity: 1)
        allow(EInvoice::SubmitJob).to receive(:perform_later)
      end

      it "creates an individual e-invoice, never consolidated" do
        expect {
          described_class.perform_now(booking.id)
        }.to change(EInvoiceSubmission, :count).by(1)

        submission = EInvoiceSubmission.last
        expect(submission.consolidated).to be false
        expect(EInvoice::SubmitJob).to have_received(:perform_later).with(submission.id)
      end
    end

    context "when booking is below threshold and not requested by guest" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 300.0)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 300.0, quantity: 1)
      end

      it "creates a pending consolidated submission without submitting" do
        expect {
          described_class.perform_now(booking.id)
        }.to change(EInvoiceSubmission, :count).by(1)

        submission = EInvoiceSubmission.last
        expect(submission.status).to eq("pending")
        expect(submission.consolidated).to be true
        expect(submission.requested_by_guest).to be false
      end
    end

    context "when guest requests the e-invoice" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 300.0)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 300.0, quantity: 1)
        allow(EInvoice::SubmitJob).to receive(:perform_later)
      end

      it "creates and submits individual e-invoice marked as guest requested" do
        expect {
          described_class.perform_now(booking.id, requested_by_guest: true)
        }.to change(EInvoiceSubmission, :count).by(1)

        submission = EInvoiceSubmission.last
        expect(submission.requested_by_guest).to be true
        expect(submission.requested_at).to be_present
        expect(submission.consolidated).to be false
        expect(EInvoice::SubmitJob).to have_received(:perform_later).with(submission.id)
      end
    end

    context "when guest requests and pending consolidated placeholder exists" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 300.0)
      end

      let!(:existing_consolidated) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "pending", consolidated: true,
          requested_by_guest: false)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 300.0, quantity: 1)
        allow(EInvoice::SubmitJob).to receive(:perform_later)
      end

      it "cancels the consolidated placeholder and creates individual submission" do
        expect {
          described_class.perform_now(booking.id, requested_by_guest: true)
        }.to change(EInvoiceSubmission, :count).by(1)

        existing_consolidated.reload
        expect(existing_consolidated.status).to eq("cancelled")
        expect(existing_consolidated.error_details["converted_to_individual"]).to be true

        submission = EInvoiceSubmission.where(status: "pending").last
        expect(submission.requested_by_guest).to be true
        expect(submission.consolidated).to be false
        expect(EInvoice::SubmitJob).to have_received(:perform_later).with(submission.id)
      end
    end

    context "when guest requests and booking already issued" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 300.0)
      end

      let!(:existing_issued) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "submitted", consolidated: false,
          requested_by_guest: true, uuid: "existing-uuid")
      end

      before do
        create(:booking_room, booking: booking, subtotal: 300.0, quantity: 1)
        allow(EInvoice::SubmitJob).to receive(:perform_later)
      end

      it "does not create duplicate and does not submit" do
        expect {
          described_class.perform_now(booking.id, requested_by_guest: true)
        }.not_to change(EInvoiceSubmission, :count)

        expect(EInvoice::SubmitJob).not_to have_received(:perform_later)
      end
    end

    context "when payment has not concluded" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "pending", total_amount: 500.0)
      end

      it "does nothing" do
        expect {
          described_class.perform_now(booking.id)
        }.not_to change(EInvoiceSubmission, :count)
      end
    end

    context "when submission already exists in pending/submitted status" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 15_000.0)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 15_000.0, quantity: 1)
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "submitted")
      end

      it "does not create a duplicate" do
        expect {
          described_class.perform_now(booking.id)
        }.not_to change(EInvoiceSubmission, :count)
      end
    end

    context "when hotel-direct low-value booking (direct_hotel_payment)" do
      let(:booking) do
        create(:booking, :direct_hotel_payment, hotel: hotel,
          payment_status: "captured", total_amount: 500.0)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 500.0, quantity: 1)
      end

      it "creates a consolidated intermediary placeholder for month-end processing" do
        expect {
          described_class.perform_now(booking.id)
        }.to change(EInvoiceSubmission, :count).by(1)

        submission = EInvoiceSubmission.last
        expect(submission.document_scenario).to eq("hotel_intermediary_guest_invoice")
        expect(submission.submission_mode).to eq("intermediary")
        expect(submission.consolidated).to be true
      end
    end

    context "when guest requests and pending individual submission already exists" do
      let(:booking) do
        create(:booking, hotel: hotel, payment_status: "captured", total_amount: 300.0)
      end

      let!(:existing_pending) do
        create(:e_invoice_submission,
          hotel: hotel, booking: booking,
          document_scenario: "guest_invoice",
          status: "pending", consolidated: false,
          requested_by_guest: true)
      end

      before do
        create(:booking_room, booking: booking, subtotal: 300.0, quantity: 1)
        allow(EInvoice::SubmitJob).to receive(:perform_later)
      end

      it "no-ops instead of creating duplicate" do
        expect {
          described_class.perform_now(booking.id, requested_by_guest: true)
        }.not_to change(EInvoiceSubmission, :count)

        expect(EInvoice::SubmitJob).not_to have_received(:perform_later)
      end
    end
  end
end
