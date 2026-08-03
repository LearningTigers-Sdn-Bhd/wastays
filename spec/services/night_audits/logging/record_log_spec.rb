require "rails_helper"

RSpec.describe NightAudits::Logging::RecordLog do
  it "backs the public audit logger" do
    audit = create(:night_audit)

    expect {
      described_class.call!(night_audit: audit, user: nil, action_type: "completed", message: "Done")
    }.to change(audit.night_audit_logs, :count).by(1)
  end
end
