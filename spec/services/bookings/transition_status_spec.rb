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
        }.to have_enqueued_job(WebhookBroadcastJob).with('booking_checked_in', anything)
          .and have_enqueued_job(Notifications::DeliverJob).exactly(2).times

        expect(booking.reload.status).to eq("checked_in")
        expect(booking.checked_in_at).to be_within(1.second).of(timestamp)
      end
    end

    context "when status is completed" do
      let(:booking) { create(:booking, status: "checked_in") }
      subject { described_class.new(booking: booking, status: "completed", timestamp: timestamp) }

      it "updates status and checked_out_at" do
        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to have_enqueued_job(WebhookBroadcastJob).with('booking_completed', anything)

        expect(booking.reload.status).to eq("completed")
        expect(booking.checked_out_at).to be_within(1.second).of(timestamp)
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
        }.to have_enqueued_job(WebhookBroadcastJob).with('booking_cancelled', anything)

        expect(booking.reload.status).to eq("cancelled")
      end
    end

    it "returns failure for unsupported status" do
      subject = described_class.new(booking: booking, status: "invalid")
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to include("Unsupported status transition")
    end

    it "handles update failures" do
      allow(booking).to receive(:update).and_return(false)
      allow(booking.errors).to receive(:full_messages).and_return([ "Error" ])

      subject = described_class.new(booking: booking, status: "checked_in")
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to eq("Error")
    end
  end
end
