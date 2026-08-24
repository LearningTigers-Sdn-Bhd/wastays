# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendWhatsappInvoiceJob, type: :job do
  let(:hotel)     { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "pending",
      check_in: Date.current + 5.days,
      check_out: Date.current + 7.days,
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      subtotal: 300.0,
      room_type_snapshot: { "name" => room_type.name }
    )
  end
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, status: "closed", invoice_number: 123) }

  describe "#perform" do
    it "enqueues or runs a WebhookBroadcastJob" do
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 300)

      # Since SendWhatsappInvoiceJob calls WebhookBroadcastJob.perform_now
      expect(WebhookBroadcastJob).to receive(:perform_now).with("booking_confirmed", hash_including(
        confirmation_token: booking.confirmation_token,
        guest_name: booking.guest_name
      ), hotel_id: booking.hotel_id)

      described_class.new.perform(booking.id)
    end

    it "skips bookings without a closed folio" do
      expect(WebhookBroadcastJob).not_to receive(:perform_now)

      described_class.new.perform(booking.id)
    end

    context "when booking does not exist" do
      it "silently returns without error" do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end
    end
  end
end
