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

  it "builds pre-arrival email with stage and booking details" do
    pre_arrival_delivery = NotificationDelivery.create!(
      hotel: delivery.hotel,
      booking: delivery.booking,
      notification_type: "pre_arrival_notification",
      channel: "email",
      trigger_event: "booking_confirmed",
      status: "pending",
      idempotency_key: "#{delivery.hotel_id}:#{delivery.booking_id}:pre_arrival_notification:email:d1",
      payload: {
        guest_name: delivery.booking.guest_name,
        hotel_name: delivery.hotel.name,
        confirmation_token: delivery.booking.confirmation_token,
        check_in: delivery.booking.check_in.to_s,
        check_out: delivery.booking.check_out.to_s,
        stage: "d1",
        scheduled_for: Time.current.iso8601
      }
    )

    pre_arrival_mail = described_class.pre_arrival_notification(pre_arrival_delivery)

    expect(pre_arrival_mail.to).to eq([ delivery.booking.guest_email ])
    expect(pre_arrival_mail.subject).to include("D1 reminder")
    expect(pre_arrival_mail.body.encoded).to include(delivery.booking.confirmation_token)
  end

  it "builds check-out receipt email with folio summary and invoice link" do
    checkout_delivery = NotificationDelivery.create!(
      hotel: delivery.hotel,
      booking: delivery.booking,
      notification_type: "check_out_receipt_message",
      channel: "email",
      trigger_event: "booking_completed",
      status: "pending",
      idempotency_key: "#{delivery.hotel_id}:#{delivery.booking_id}:check_out_receipt_message:email:booking_completed",
      payload: {
        guest_name: delivery.booking.guest_name,
        hotel_name: delivery.hotel.name,
        confirmation_token: delivery.booking.confirmation_token,
        check_in: "2026-05-08",
        check_out: "2026-05-09",
        currency: "MYR",
        line_items: [ { description: "Executive King", quantity: 1, amount: 240.0, room_number: "101" } ],
        tax_items: [ { description: "Tourism Tax", amount: 10.0 } ],
        line_items_total: 240.0,
        tax_total: 10.0,
        derived_grand_total: 250.0,
        booking_total: 250.0,
        totals_mismatch: false,
        totals_mismatch_amount: 0.0,
        invoice_url: "https://example.com/invoices/#{delivery.booking.confirmation_token}"
      }
    )

    checkout_mail = described_class.check_out_receipt_message(checkout_delivery)

    expect(checkout_mail.to).to eq([ delivery.booking.guest_email ])
    expect(checkout_mail.subject).to include("checkout receipt")
    expect(checkout_mail.body.encoded).to include("Folio Summary")
    expect(checkout_mail.body.encoded).to include("Tourism Tax")
    expect(checkout_mail.body.encoded).to include("View Invoice")
    expect(checkout_mail.body.encoded).to include(checkout_delivery.payload["invoice_url"])
  end

  it "includes mismatch note when totals_mismatch is true" do
    checkout_delivery = NotificationDelivery.create!(
      hotel: delivery.hotel,
      booking: delivery.booking,
      notification_type: "check_out_receipt_message",
      channel: "email",
      trigger_event: "booking_completed",
      status: "pending",
      idempotency_key: "#{delivery.hotel_id}:#{delivery.booking_id}:check_out_receipt_message:email:booking_completed:mismatch",
      payload: {
        guest_name: delivery.booking.guest_name,
        hotel_name: delivery.hotel.name,
        confirmation_token: delivery.booking.confirmation_token,
        check_in: "2026-05-08",
        check_out: "2026-05-09",
        currency: "MYR",
        line_items: [ { description: "Executive King", quantity: 1, amount: 200.0 } ],
        tax_items: [],
        line_items_total: 200.0,
        tax_total: 0.0,
        derived_grand_total: 200.0,
        booking_total: 250.0,
        totals_mismatch: true,
        totals_mismatch_amount: 50.0,
        invoice_url: "https://example.com/invoices/#{delivery.booking.confirmation_token}"
      }
    )

    checkout_mail = described_class.check_out_receipt_message(checkout_delivery)

    expect(checkout_mail.body.encoded).to include("Receipt note")
    expect(checkout_mail.body.encoded).to include("50.00")
  end
end
