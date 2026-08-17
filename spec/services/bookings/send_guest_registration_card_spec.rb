# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::SendGuestRegistrationCard do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_email: "guest@example.com") }
  let(:user) { create(:user) }

  describe ".call" do
    it "queues a delivery to the guest and returns the recipient" do
      booking.create_guest_registration_card!(hotel: hotel)

      expect {
        result = described_class.call(booking: booking, user: user)

        expect(result.success?).to be(true)
        expect(result.recipient).to eq("guest@example.com")

        delivery = result.delivery
        expect(delivery.notification_type).to eq("guest_registration_card")
        expect(delivery.channel).to eq("email")
        expect(delivery.trigger_event).to eq("manual")
        expect(delivery.status).to eq("pending")
        expect(delivery.payload["recipient_email"]).to eq("guest@example.com")
        expect(delivery.payload["requested_by_name"]).to eq(user.name)
      }.to have_enqueued_job(Notifications::DeliverJob)
    end

    it "lets staff send the same card more than once" do
      booking.create_guest_registration_card!(hotel: hotel)

      expect {
        2.times { described_class.call(booking: booking, user: user) }
      }.to change(NotificationDelivery, :count).by(2)
    end

    it "fails when the booking has no guest email" do
      booking.update_columns(guest_email: nil)
      booking.create_guest_registration_card!(hotel: hotel)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to eq("This booking has no guest email address to send to.")
    end

    it "fails when the registration card has not been created yet" do
      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(false)
      expect(result.error).to eq("The registration card has not been created yet.")
    end
  end
end
