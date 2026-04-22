require "rails_helper"

RSpec.describe Admin::GlobalSearchService do
  let(:hotel) { create(:hotel, name: "Ocean Bay") }
  let!(:booking) { create(:booking, hotel: hotel, guest_name: "Alice", confirmation_token: "WS-ALICE01") }

  it "returns page results for empty query" do
    results = described_class.new("").perform

    expect(results).to include(hash_including(title: "Dashboard", group: "Pages"))
  end

  it "returns booking results for booking query" do
    results = described_class.new("alice").perform

    expect(results).to include(hash_including(title: a_string_including("WS-ALICE01"), group: "Bookings"))
  end

  it "provides quick actions" do
    actions = described_class.new("").quick_actions
    expect(actions.map { |a| a[:label] }).to include("Go to bookings", "Go to hotels")
  end
end
