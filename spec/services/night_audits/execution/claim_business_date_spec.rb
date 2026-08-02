require "rails_helper"

RSpec.describe NightAudits::Execution::ClaimBusinessDate do
  it "claims the current business date for audit" do
    hotel = create(:hotel, :without_current_business_date)
    date = Date.current

    result = described_class.call(hotel: hotel, business_date: date, actor: nil)

    expect(result.error).to be_nil
    expect(result.business_date).to be_audit_running
  end

  it "rejects a business date that is already running" do
    hotel = create(:hotel, :without_current_business_date)
    create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_running")

    result = described_class.call(hotel: hotel, business_date: Date.current, actor: nil)

    expect(result.error).to eq("Night audit is already running for this date.")
  end
end
