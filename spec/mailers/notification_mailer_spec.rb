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
    expect(mail.to).to eq([ delivery.booking.guest_email ])
  end

  it "includes the hotel name in the subject" do
    expect(mail.subject).to include("Cedar Stay")
  end

  it "builds post-stay review email with review link" do
    post_stay_delivery = NotificationDelivery.create!(
      hotel: delivery.hotel,
      booking: delivery.booking,
      notification_type: "post_stay_review_request",
      channel: "email",
      trigger_event: "booking_completed",
      status: "pending",
      idempotency_key: "#{delivery.hotel_id}:#{delivery.booking_id}:post_stay_review_request:email:booking_completed",
      payload: {
        guest_name: delivery.booking.guest_name,
        hotel_name: delivery.hotel.name,
        confirmation_token: delivery.booking.confirmation_token,
        check_out: delivery.booking.check_out.to_s,
        review_link: "https://g.page/r/example/review"
      }
    )

    review_mail = described_class.post_stay_review_request(post_stay_delivery)

    expect(review_mail.to).to eq([ delivery.booking.guest_email ])
    expect(review_mail.subject).to include("Cedar Stay")
    expect(review_mail.body.encoded).to include("https://g.page/r/example/review")
  end
end
