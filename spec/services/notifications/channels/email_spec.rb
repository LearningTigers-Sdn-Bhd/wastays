require "rails_helper"

RSpec.describe Notifications::Channels::Email do
  it "sends check-in confirmation email" do
    delivery = create(:notification_delivery,
      channel: "email",
      notification_type: "check_in_confirmation",
      trigger_event: "booking_checked_in")

    expect {
      described_class.new(delivery: delivery).call
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end

  it "sends post-stay review request email" do
    delivery = create(:notification_delivery,
      channel: "email",
      notification_type: "post_stay_review_request",
      trigger_event: "booking_completed",
      payload: {
        guest_name: "Aisha",
        hotel_name: "Cedar Stay",
        confirmation_token: "WS-TEST123",
        check_out: "2026-05-09",
        review_link: "https://g.page/r/example/review"
      })

    expect {
      described_class.new(delivery: delivery).call
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end

  it "sends pre-arrival notification email" do
    delivery = create(:notification_delivery,
      channel: "email",
      notification_type: "pre_arrival_notification",
      trigger_event: "booking_confirmed",
      payload: {
        guest_name: "Aisha",
        hotel_name: "Cedar Stay",
        confirmation_token: "WS-TEST123",
        check_in: "2026-05-10",
        check_out: "2026-05-11",
        stage: "d1",
        scheduled_for: "2026-05-09T00:00:00+08:00"
      })

    expect {
      described_class.new(delivery: delivery).call
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end

  it "sends check-out receipt message email" do
    delivery = create(:notification_delivery,
      channel: "email",
      notification_type: "check_out_receipt_message",
      trigger_event: "booking_completed",
      payload: {
        guest_name: "Aisha",
        hotel_name: "Cedar Stay",
        confirmation_token: "WS-TEST123",
        check_in: "2026-05-08",
        check_out: "2026-05-09",
        currency: "MYR",
        line_items: [ { description: "Executive King", quantity: 1, amount: 240.0 } ],
        tax_items: [ { description: "Tourism Tax", amount: 10.0 } ],
        line_items_total: 240.0,
        tax_total: 10.0,
        derived_grand_total: 250.0,
        booking_total: 250.0,
        totals_mismatch: false,
        totals_mismatch_amount: 0.0,
        invoice_url: "https://example.com/invoice.pdf"
      })

    expect {
      described_class.new(delivery: delivery).call
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end
end
