# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::RecordLog do
  it "records a Night Audit log with unchanged attributes" do
    night_audit = create(:night_audit)
    user = create(:user)

    log = described_class.call!(
      night_audit: night_audit,
      user: user,
      action_type: "process_started",
      message: "Night audit started",
      metadata: { phase: "pre_close" }
    )

    expect(log).to have_attributes(
      night_audit: night_audit,
      hotel: night_audit.hotel,
      user: user,
      action_type: "process_started",
      message: "Night audit started",
      metadata: { "phase" => "pre_close" }
    )
  end
end
