# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::WebhookTriggerService do
  let(:booking) { create(:booking) }
  let(:service) { described_class.new(booking) }

  describe "#trigger" do
    it "enqueues a WebhookBroadcastJob with the correct event and payload" do
      expect {
        service.trigger(:booking_confirmed)
      }.to have_enqueued_job(WebhookBroadcastJob).with("booking_confirmed", Hash)
    end

    it "builds a comprehensive payload" do
      # We test the private build_payload indirectly by checking the job arguments
      # but we can also test it more specifically if we want
      payload = service.send(:build_payload, :booking_confirmed)

      expect(payload[:booking_id]).to eq(booking.id)
      expect(payload[:confirmation_token]).to eq(booking.confirmation_token)
      expect(payload[:status]).to eq(booking.status)
      expect(payload[:guest][:name]).to eq(booking.guest_name)
      expect(payload[:hotel][:name]).to eq(booking.hotel.name)
      expect(payload[:stay][:check_in]).to eq(booking.check_in)
    end
  end
end
