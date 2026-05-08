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
end
