require "rails_helper"

RSpec.describe NightAudits::Resolutions::RefreshSnapshot do
  it "updates both audit snapshots" do
    night_audit = create(:night_audit, summary: { "existing" => true })
    business_date = night_audit.hotel.current_business_date_record
    business_date.update!(status: "audit_blocked")
    evaluation = { blocked_details: { "missing_folio" => [] }, exceptions: {}, summary: { "arrivals_count" => 1 } }

    described_class.call!(night_audit: night_audit, business_date_record: business_date, evaluation: evaluation)

    expect(night_audit.reload.summary).to include("existing" => true, "arrivals_count" => 1)
    expect(business_date.reload.blockers_snapshot).to eq("missing_folio" => [])
  end
end
