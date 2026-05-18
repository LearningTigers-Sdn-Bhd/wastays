# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::TransitionStatus do
  let(:booking) { create(:booking, status: "confirmed") }
  let(:timestamp) { Time.current }

  describe "#call" do
    context "when status is checked_in" do
      subject { described_class.new(booking: booking, status: "checked_in", timestamp: timestamp) }

      it "updates status and checked_in_at" do
        NotificationConfig.create!(hotel: booking.hotel, notification_type: "check_in_confirmation", enabled: true, channels: %w[whatsapp email], settings: {})

        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change(BookingAuditLog, :count).by(1)
          .and have_enqueued_job(WebhookBroadcastJob).with('booking_checked_in', anything)
          .and have_enqueued_job(Notifications::DeliverJob).exactly(2).times

        expect(booking.reload.status).to eq("checked_in")
        expect(booking.checked_in_at).to be_within(1.second).of(timestamp)
        expect(booking.booking_folio).to be_present
        expect(booking.booking_folio.hotel).to eq(booking.hotel)
        expect(booking.booking_folio.folio_number).to be_present

        log = BookingAuditLog.last
        expect(log.action_type).to eq("check_in")
        expect(log.auditable).to eq(booking)
      end

      it "rolls back the folio when payment sync fails" do
        create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

        failed_result = OpenStruct.new(success?: false, error: "posting blocked")
        insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
        allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

        result = subject.call

        expect(result.success?).to be false
        expect(result.error).to include("posting blocked")
        expect(booking.reload.status).to eq("confirmed")
        expect(booking.booking_folio).to be_nil
      end

      it "allows different hotels to use the same folio number" do
        other_booking = create(:booking, status: "confirmed")
        allow(HotelCounter).to receive(:increment!).and_call_original
        allow(HotelCounter).to receive(:increment!).with(hotel: booking.hotel, type: "folio").and_return(1)
        allow(HotelCounter).to receive(:increment!).with(hotel: other_booking.hotel, type: "folio").and_return(1)

        first_result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call
        second_result = described_class.new(booking: other_booking, status: "checked_in", timestamp: timestamp).call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(booking.reload.booking_folio.folio_number).to eq(1)
        expect(other_booking.reload.booking_folio.folio_number).to eq(1)
      end

      it "silently no-ops when the booking is already checked in" do
        create(:booking_room, booking: booking, subtotal: 100.0)
        first_result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call
        expect(first_result.success?).to be true
        create(:night_audit, hotel: booking.hotel, business_date: (timestamp + 1.hour).to_date, status: "completed")

        booking.reload
        folio = booking.booking_folio
        checked_in_at = booking.checked_in_at
        guest_registration_number = booking.guest_registration_number
        folio_number = folio.folio_number

        expect {
          second_result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp + 1.hour).call
          expect(second_result.success?).to be true
        }.to change(BookingAuditLog, :count).by(0)
          .and change(BookingFolio, :count).by(0)
          .and change(FolioTransaction, :count).by(0)
          .and have_enqueued_job(WebhookBroadcastJob).exactly(0).times
          .and have_enqueued_job(Notifications::DeliverJob).exactly(0).times

        booking.reload
        expect(booking.checked_in_at).to eq(checked_in_at)
        expect(booking.guest_registration_number).to eq(guest_registration_number)
        expect(booking.booking_folio.folio_number).to eq(folio_number)
      end

      it "repairs a checked-in booking with a missing folio without check-in side effects" do
        checked_in_at = 1.hour.ago
        booking.update!(status: "checked_in", checked_in_at: checked_in_at, guest_registration_number: 99)
        create(:booking_room, booking: booking, subtotal: 100.0)
        create(:night_audit, hotel: booking.hotel, business_date: booking.check_in, status: "completed")

        expect {
          result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call
          expect(result.success?).to be true
        }.to change(BookingFolio, :count).by(1)
          .and change(FolioTransaction, :count).by(0)
          .and change(BookingAuditLog, :count).by(0)
          .and have_enqueued_job(WebhookBroadcastJob).exactly(0).times
          .and have_enqueued_job(Notifications::DeliverJob).exactly(0).times

        booking.reload
        expect(booking.checked_in_at.to_i).to eq(checked_in_at.to_i)
        expect(booking.guest_registration_number).to eq(99)
        expect(booking.booking_folio).to be_present
      end

      it "fails when a completed booking is checked in again" do
        booking.update!(status: "completed")

        result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call

        expect(result.success?).to be false
        expect(result.error).to include("Cannot check in booking with status completed")
        expect(booking.reload.status).to eq("completed")
      end

      it "fails when a cancelled booking is checked in again" do
        booking.update!(status: "cancelled")

        result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call

        expect(result.success?).to be false
        expect(result.error).to include("Cannot check in booking with status cancelled")
        expect(booking.reload.status).to eq("cancelled")
      end
    end

    context "when status is completed" do
      let(:booking) { create(:booking, status: "checked_in") }
      subject { described_class.new(booking: booking, status: "completed", timestamp: timestamp) }

      def create_settled_folio
        folio = create(:booking_folio, booking: booking, status: "open")
        create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
        create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)
        folio
      end

      it "updates status and checked_out_at" do
        folio = create_settled_folio
        NotificationConfig.create!(
          hotel: booking.hotel,
          notification_type: "post_stay_review_request",
          enabled: true,
          channels: %w[whatsapp],
          settings: { "review_link" => "https://g.page/r/example/review", "send_delay_hours" => 2 }
        )
        NotificationConfig.create!(
          hotel: booking.hotel,
          notification_type: "check_out_receipt_message",
          enabled: true,
          channels: %w[email whatsapp],
          settings: {}
        )

        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change(BookingAuditLog, :count).by(1)
          .and have_enqueued_job(WebhookBroadcastJob).with('booking_completed', anything)
          .and have_enqueued_job(Notifications::DeliverJob).exactly(3).times

        expect(booking.reload.status).to eq("completed")
        expect(booking.checked_out_at).to be_within(1.second).of(timestamp)
        expect(folio.reload.status).to eq("closed")

        log = BookingAuditLog.last
        expect(log.action_type).to eq("check_out")
        expect(log.metadata["folio_id"]).to eq(folio.id)
      end

      it "fails when the folio has an outstanding balance" do
        folio = create(:booking_folio, booking: booking, status: "open")
        create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

        expect {
          result = subject.call
          expect(result.success?).to be(false)
          expect(result.error).to include("outstanding balance")
        }.to change(BookingAuditLog, :count).by(0)
          .and have_enqueued_job(WebhookBroadcastJob).exactly(0).times
          .and have_enqueued_job(Notifications::DeliverJob).exactly(0).times

        expect(booking.reload.status).to eq("checked_in")
        expect(booking.checked_out_at).to be_nil
        expect(folio.reload.status).to eq("open")
      end

      it "fails when the folio has a credit balance" do
        folio = create(:booking_folio, booking: booking, status: "open")
        create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 50.0)

        result = subject.call

        expect(result.success?).to be(false)
        expect(result.error).to include("credit balance")
        expect(booking.reload.status).to eq("checked_in")
        expect(folio.reload.status).to eq("open")
      end

      it "fails without a folio" do
        result = subject.call

        expect(result.success?).to be(false)
        expect(result.error).to eq("Booking has no folio.")
        expect(booking.reload.status).to eq("checked_in")
      end
    end

    context "when status is cancelled" do
      subject { described_class.new(booking: booking, status: "cancelled") }

      it "updates status and releases inventory" do
        inventory_manager = instance_double(Bookings::InventoryManager)
        expect(Bookings::InventoryManager).to receive(:new).with(booking).and_return(inventory_manager)
        expect(inventory_manager).to receive(:release)

        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change(BookingAuditLog, :count).by(1)
          .and have_enqueued_job(WebhookBroadcastJob).with('booking_cancelled', anything)

        expect(booking.reload.status).to eq("cancelled")

        log = BookingAuditLog.last
        expect(log.action_type).to eq("cancel")
      end
    end

    it "returns failure for unsupported status" do
      subject = described_class.new(booking: booking, status: "invalid")
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to include("Unsupported status transition")
    end

    it "handles update failures" do
      allow(booking).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(booking))
      allow(booking.errors).to receive(:full_messages).and_return([ "Error" ])

      subject = described_class.new(booking: booking, status: "checked_in")
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to eq("Error")
    end
  end
end
