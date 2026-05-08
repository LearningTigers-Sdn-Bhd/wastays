require "rails_helper"

RSpec.describe Notifications::Channels::Email do
  it "sends check-in confirmation email" do
    delivery = create(:notification_delivery, channel: "email")

    expect {
      described_class.new(delivery: delivery).call
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end
end
