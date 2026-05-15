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
        expect(booking.booking_folio.folio_number).to be_present

        log = BookingAuditLog.last
        expect(log.action_type).to eq("check_in")
        expect(log.auditable).to eq(booking)
      end

      it "rolls back the folio when initial charge posting fails" do
        create(:booking_room, booking: booking, subtotal: 100.0)

        failed_result = OpenStruct.new(success?: false, error: "posting blocked")
        insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
        allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

        result = subject.call

        expect(result.success?).to be false
        expect(result.error).to include("posting blocked")
        expect(booking.reload.status).to eq("confirmed")
        expect(booking.booking_folio).to be_nil
      end
    end

    context "when status is completed" do
      let(:booking) { create(:booking, status: "checked_in") }
      subject { described_class.new(booking: booking, status: "completed", timestamp: timestamp) }

      it "updates status and checked_out_at" do
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

        log = BookingAuditLog.last
        expect(log.action_type).to eq("check_out")
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
