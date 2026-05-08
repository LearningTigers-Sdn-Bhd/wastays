require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  let(:delivery) do
    hotel = create(:hotel, name: "Cedar Stay")
    booking = create(:booking, hotel: hotel, guest_email: "guest@example.com", guest_name: "Aisha", status: "checked_in")
    NotificationDelivery.create!(
      hotel: hotel,
      booking: booking,
      notification_type: "check_in_confirmation",
      channel: "email",
      trigger_event: "booking_checked_in",
      status: "pending",
      idempotency_key: "#{hotel.id}:#{booking.id}:check_in_confirmation:email:booking_checked_in",
      payload: { guest_name: booking.guest_name, hotel_name: hotel.name, checked_in_at: Time.current.iso8601 }
    )
  end

  subject(:mail) { described_class.check_in_confirmation(delivery) }

  it "sends to the booking guest email" do
    expect(mail.to).to eq([delivery.booking.guest_email])
  end

  it "includes the hotel name in the subject" do
    expect(mail.subject).to include("Cedar Stay")
  end
end
