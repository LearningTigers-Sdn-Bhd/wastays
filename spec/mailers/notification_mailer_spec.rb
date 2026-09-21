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
        tax_line: [ { description: "Tourism Tax", quantity: 1, amount: 10.0 } ],
        line_items_total: 240.0,
        tax_total: 10.0,
        derived_grand_total: 250.0,
        booking_total: 250.0,
        totals_mismatch: false,
        totals_mismatch_amount: 0.0,
        document_type: "receipt",
        invoice_url: "https://example.com/invoices/#{delivery.booking.confirmation_token}"
      }
    )

    checkout_mail = described_class.check_out_receipt_message(checkout_delivery)
    html_body = checkout_mail.html_part.body.decoded

    expect(checkout_mail.to).to eq([ delivery.booking.guest_email ])
    expect(checkout_mail.subject).to include("checkout invoice")
    expect(html_body).to include("Charges")
    expect(html_body).to include("Tourism Tax")
    expect(html_body).to include("View Receipt")
    expect(html_body).to include(checkout_delivery.payload["invoice_url"])
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
        tax_line: [],
        line_items_total: 200.0,
        tax_total: 0.0,
        derived_grand_total: 200.0,
        booking_total: 250.0,
        totals_mismatch: true,
        totals_mismatch_amount: 50.0,
        document_type: "receipt",
        invoice_url: "https://example.com/invoices/#{delivery.booking.confirmation_token}"
      }
    )

    checkout_mail = described_class.check_out_receipt_message(checkout_delivery)
    html_body = checkout_mail.html_part.body.decoded

    expect(html_body).to include("Note: line-item total differs")
    expect(html_body).to include("50.00")
  end

  it "builds in-stay messaging email with rule label" do
    in_stay_delivery = NotificationDelivery.create!(
      hotel: delivery.hotel,
      booking: delivery.booking,
      notification_type: "in_stay_guest_messaging",
      channel: "email",
      trigger_event: "booking_confirmed",
      status: "pending",
      idempotency_key: "#{delivery.hotel_id}:#{delivery.booking_id}:in_stay_guest_messaging:email:mid_stay",
      payload: {
        guest_name: delivery.booking.guest_name,
        hotel_name: delivery.hotel.name,
        confirmation_token: delivery.booking.confirmation_token,
        check_in: "2026-05-10",
        check_out: "2026-05-12",
        rule_key: "mid_stay",
        rule_label: "Mid-stay check-in",
        scheduled_for: Time.current.iso8601
      }
    )

    in_stay_mail = described_class.in_stay_guest_messaging(in_stay_delivery)

    expect(in_stay_mail.to).to eq([ delivery.booking.guest_email ])
    expect(in_stay_mail.subject).to include("stay")
    expect(in_stay_mail.body.encoded).to include("Mid-stay check-in")
    expect(in_stay_mail.body.encoded).to include(delivery.booking.confirmation_token)
  end

  # The only mails in this class addressed to somebody other than the guest.
  describe "agent payment mails" do
    let(:hotel) { create(:hotel, name: "Cedar Stay", status: "live") }
    let(:corporate_user) { create(:user, :corporate, email: "agent@agency.test") }
    let(:relationship) do
      create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
    end
    let(:booking) do
      create(:booking, hotel: hotel, hotel_corporate_account: relationship, corporate_booked_by: corporate_user,
                       guest_email: "guest@example.com", status: "confirmed", payment_status: "pending",
                       payment_due_at: 6.hours.from_now)
    end

    def agent_delivery(type, extra: {})
      payload = Notifications::PayloadBuilders::AgentPaymentNotice.new(
        booking: booking, notification_type: type, trigger_event: "spec", extra: extra
      ).call
      NotificationDelivery.create!(
        hotel: hotel, booking: booking, notification_type: type, channel: "email",
        trigger_event: "spec", status: "pending", idempotency_key: "spec:#{type}", payload: payload
      )
    end

    it "writes to the agent, not the guest" do
      mail = described_class.agent_payment_reminder(agent_delivery("agent_payment_reminder"))

      expect(mail.to).to eq([ "agent@agency.test" ])
      expect(mail.to).not_to include("guest@example.com")
    end

    it "names the reservation and states the deadline with its zone" do
      mail = described_class.agent_payment_reminder(agent_delivery("agent_payment_reminder"))

      expect(mail.subject).to include(booking.formatted_reservation_number)
      expect(mail.body.encoded).to include("Pay by")
    end

    it "offers nothing to click once the payment has been accepted" do
      mail = described_class.agent_payment_approved(agent_delivery("agent_payment_approved"))

      expect(mail.subject).to include("Payment confirmed")
      expect(mail.body.encoded).not_to include("Send your transfer slip")
    end

    # A rejection an agent cannot act on costs them the rooms twice.
    it "quotes the hotel's reason when a slip is rejected" do
      delivery = agent_delivery("agent_payment_rejected", extra: { rejection_reason: "Amount did not match" })

      mail = described_class.agent_payment_rejected(delivery)

      expect(mail.subject).to include("Action needed")
      expect(mail.body.encoded).to include("Amount did not match")
    end

    it "says plainly that the rooms are gone when they have been released" do
      mail = described_class.agent_booking_released(agent_delivery("agent_booking_released"))

      expect(mail.subject).to start_with("Cancelled:")
      expect(mail.body.encoded).to include("returned to sale")
    end
  end
end
