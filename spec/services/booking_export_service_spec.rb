require "rails_helper"

RSpec.describe BookingExportService do
  it "exports breakdown csv with booking rows" do
    booking = create(:booking, confirmation_token: "WS-ABC", guest_name: "Jane")

    csv = described_class.new([ booking ]).generate_breakdown_csv

    expect(csv).to include("Confirmation Token")
    expect(csv).to include("WS-ABC")
    expect(csv).to include("Jane")
  end
end
