# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::RunScheduledJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:business_date) { Date.new(2026, 4, 23) }

  it "runs only for approved and live hotels using yesterday's business date" do
    approved_hotel = create(:hotel, :without_current_business_date, status: "approved")
    live_hotel = create(:hotel, :without_current_business_date, status: "live")
    create(:hotel, :without_current_business_date, status: "registered")

    allow(NightAudits::RunJob).to receive(:perform_later)

    described_class.perform_now(business_date)

    approved_audit = approved_hotel.night_audits.find_by(business_date: business_date)
    live_audit = live_hotel.night_audits.find_by(business_date: business_date)

    expect(approved_audit).to be_present
    expect(approved_audit.status).to eq("pending")
    expect(approved_audit.trigger_mode).to eq("scheduled")

    expect(live_audit).to be_present
    expect(live_audit.status).to eq("pending")
    expect(live_audit.trigger_mode).to eq("scheduled")

    expect(NightAudits::RunJob).to have_received(:perform_later).with(approved_audit.id, nil)
    expect(NightAudits::RunJob).to have_received(:perform_later).with(live_audit.id, nil)
  end

  it "continues when one hotel raises" do
    failing_hotel = create(:hotel, :without_current_business_date, status: "approved")
    succeeding_hotel = create(:hotel, :without_current_business_date, status: "live")

    allow_any_instance_of(NightAudit).to receive(:save).and_wrap_original do |original_method, *args|
      instance = original_method.receiver
      if instance.hotel_id == failing_hotel.id
        raise StandardError, "boom"
      else
        original_method.call(*args)
      end
    end
    allow(NightAudits::RunJob).to receive(:perform_later)

    expect { described_class.perform_now(business_date) }.not_to raise_error
    expect(succeeding_hotel.night_audits.find_by(business_date: business_date)).to be_present
    expect(NightAudits::RunJob).to have_received(:perform_later).once
  end

  it "uses the hotel's current accounting date after it becomes closable" do
    hotel = create(:hotel, :without_current_business_date, status: "live", time_zone: "Kuala Lumpur", business_starts_at: "08:00", business_ends_at: "02:00")
    create(:hotel_business_date, hotel: hotel, business_date: Date.new(2026, 5, 18), status: "open")
    allow(NightAudits::RunJob).to receive(:perform_later)

    travel_to(Time.find_zone("Kuala Lumpur").local(2026, 5, 19, 2, 35)) do
      described_class.perform_now
    end

    audit = hotel.night_audits.find_by(business_date: Date.new(2026, 5, 18))
    expect(audit).to be_present
    expect(NightAudits::RunJob).to have_received(:perform_later).with(audit.id, nil)
  end

  it "does not schedule the current accounting date before it is closable" do
    hotel = create(:hotel, :without_current_business_date, status: "live", time_zone: "Kuala Lumpur", business_starts_at: "08:00", business_ends_at: "02:00")
    create(:hotel_business_date, hotel: hotel, business_date: Date.new(2026, 5, 18), status: "open")
    allow(NightAudits::RunJob).to receive(:perform_later)

    travel_to(Time.find_zone("Kuala Lumpur").local(2026, 5, 19, 2, 25)) do
      described_class.perform_now
    end

    yesterday_audit = hotel.night_audits.find_by(business_date: Date.new(2026, 5, 18))
    expect(yesterday_audit).to be_nil
    expect(NightAudits::RunJob).not_to have_received(:perform_later)
  end

  it "re-enqueues blocked and failed audits but skips running and completed audits" do
    hotel = create(:hotel, :without_current_business_date, status: "live")
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_blocked")
    blocked_audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "blocked")
    failed_audit = create(:night_audit, hotel: hotel, business_date: business_date + 1.day, status: "failed")
    running_audit = create(:night_audit, hotel: hotel, business_date: business_date + 2.days, status: "running")
    completed_audit = create(:night_audit, hotel: hotel, business_date: business_date + 3.days, status: "completed")
    allow(NightAudits::RunJob).to receive(:perform_later)

    described_class.perform_now(business_date)
    described_class.perform_now(business_date + 1.day)
    described_class.perform_now(business_date + 2.days)
    described_class.perform_now(business_date + 3.days)

    expect(NightAudits::RunJob).to have_received(:perform_later).with(blocked_audit.id, nil)
    expect(NightAudits::RunJob).not_to have_received(:perform_later).with(failed_audit.id, nil)
    expect(NightAudits::RunJob).not_to have_received(:perform_later).with(running_audit.id, nil)
    expect(NightAudits::RunJob).not_to have_received(:perform_later).with(completed_audit.id, nil)
  end
end
