# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::RunJob, type: :job do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: Date.current, status: "running", trigger_mode: "manual", notes: "Test notes") }

  it "calls NightAudits::Run service with correct arguments" do
    runner = instance_double(NightAudits::Run)
    expect(NightAudits::Run).to receive(:new).with(
      hotel: hotel,
      business_date: night_audit.business_date,
      performed_by_user: user,
      trigger_mode: "manual",
      notes: "Test notes",
      allow_unclosable_date: false,
      force_roll: false
    ).and_return(runner)

    expect(runner).to receive(:call)

    described_class.perform_now(night_audit.id, user.id)
  end

  it "handles nil user correctly for scheduled audits" do
    scheduled_audit = create(:night_audit, hotel: hotel, business_date: Date.current, status: "running", trigger_mode: "scheduled")
    runner = instance_double(NightAudits::Run)
    expect(NightAudits::Run).to receive(:new).with(
      hotel: hotel,
      business_date: scheduled_audit.business_date,
      performed_by_user: nil,
      trigger_mode: "scheduled",
      notes: nil,
      allow_unclosable_date: false,
      force_roll: false
    ).and_return(runner)

    expect(runner).to receive(:call)

    described_class.perform_now(scheduled_audit.id, nil)
  end

  it "passes the development-only unclosable date override to the service" do
    runner = instance_double(NightAudits::Run)
    expect(NightAudits::Run).to receive(:new).with(
      hotel: hotel,
      business_date: night_audit.business_date,
      performed_by_user: user,
      trigger_mode: "manual",
      notes: "Test notes",
      allow_unclosable_date: true,
      force_roll: false
    ).and_return(runner)

    expect(runner).to receive(:call)

    described_class.perform_now(night_audit.id, user.id, allow_unclosable_date: true)
  end
end
