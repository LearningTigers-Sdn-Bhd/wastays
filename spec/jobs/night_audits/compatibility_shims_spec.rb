# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Night Audit job compatibility shims" do
  it "forwards the legacy run job through the Night Audits job" do
    expect(HotelOps::RunNightAuditJob.superclass).to eq(NightAudits::RunJob)
  end

  it "forwards the legacy scheduled job through the Night Audits job" do
    expect(RunScheduledNightAuditsJob.superclass).to eq(NightAudits::RunScheduledJob)
  end
end
