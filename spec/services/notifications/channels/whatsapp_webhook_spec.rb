require "rails_helper"

RSpec.describe Notifications::Channels::WhatsappWebhook do
  it "delegates to WebhookBroadcastJob with a whatsapp-specific event" do
    delivery = create(:notification_delivery,
      channel: "whatsapp",
      notification_type: "check_in_confirmation",
      trigger_event: "booking_checked_in",
      payload: { guest_name: "Aisha" })

    expect(WebhookBroadcastJob).to receive(:perform_now).with("check_in_confirmation", hash_including("guest_name" => "Aisha"))

    described_class.new(delivery: delivery).call
  end

  it "uses post-stay event type for review requests" do
    delivery = create(:notification_delivery,
      channel: "whatsapp",
      notification_type: "post_stay_review_request",
      trigger_event: "booking_completed",
      payload: { review_link: "https://g.page/r/example/review" })

    expect(WebhookBroadcastJob).to receive(:perform_now).with("post_stay_review_request", hash_including("review_link" => "https://g.page/r/example/review"))

    described_class.new(delivery: delivery).call
  end

  it "uses pre-arrival event type for pre-arrival notification" do
    delivery = create(:notification_delivery,
      channel: "whatsapp",
      notification_type: "pre_arrival_notification",
      trigger_event: "booking_confirmed",
      payload: { stage: "d1", guest_name: "Aisha" })

    expect(WebhookBroadcastJob).to receive(:perform_now).with("pre_arrival_notification", hash_including("stage" => "d1"))

    described_class.new(delivery: delivery).call
  end
end
