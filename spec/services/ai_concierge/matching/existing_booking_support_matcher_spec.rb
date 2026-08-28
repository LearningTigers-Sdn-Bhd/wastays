require "rails_helper"

RSpec.describe AiConcierge::Matching::ExistingBookingSupportMatcher do
  it "routes an existing cancellation to the portal" do
    matcher = described_class.new(message: "I want to cancel my booking")

    expect(matcher.request_kind).to eq(:portal_cancellation)
  end

  it "leaves a general cancellation policy question alone" do
    matcher = described_class.new(message: "What is the cancellation policy?")

    expect(matcher.request_kind).to be_nil
  end

  it "routes explicit booking changes to staff" do
    expect(described_class.new(message: "Change my check-in date").request_kind).to eq(:unsupported_date_change)
    expect(described_class.new(message: "Change my booking check-in date").request_kind).to eq(:unsupported_date_change)
    expect(described_class.new(message: "Change my booking room").request_kind).to eq(:unsupported_room_change)
    expect(described_class.new(message: "Update the name on my reservation").request_kind).to eq(:unsupported_guest_change)
    expect(described_class.new(message: "Dispute the payment on my booking").request_kind).to eq(:unsupported_exception)
  end

  it "routes a possessive booking document request to the portal" do
    expect(described_class.new(message: "Please send my invoice").request_kind).to eq(:portal_documents)
  end
end
