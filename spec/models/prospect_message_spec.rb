require "rails_helper"

RSpec.describe ProspectMessage, type: :model do
  it "defaults sent_at on create" do
    message = described_class.create!(prospect: create(:prospect), direction: "inbound", body: "Hello")

    expect(message.sent_at).to be_present
  end
end
