# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::OperationalChangeGuard do
  let(:hotel) { create(:hotel) }
  let(:business_date) { hotel.current_business_date }

  it "allows operational changes while the business date is open" do
    expect(described_class.call!(hotel: hotel, action: :check_in)).to be(true)
  end

  it "blocks operational changes while night audit is running" do
    hotel.current_business_date_record.update!(status: "audit_running")

    expect do
      described_class.call!(hotel: hotel, action: :check_in)
    end.to raise_error(described_class::OperationalChangeBlocked, described_class::ERROR_MESSAGE)
  end

  it "allows operational changes while night audit is blocked" do
    hotel.current_business_date_record.update!(status: "audit_blocked")

    expect(described_class.call!(hotel: hotel, action: :resolve_blocker)).to be(true)
  end

  it "allows the matching active night audit to perform controlled changes" do
    hotel.current_business_date_record.update!(status: "audit_running")
    audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running")

    expect(described_class.call!(hotel: hotel, action: :review_due_out, night_audit: audit)).to be(true)
  end

  it "rejects a completed, cross-hotel, or wrong-date audit bypass" do
    hotel.current_business_date_record.update!(status: "audit_running")
    completed = create(:night_audit, hotel: hotel, business_date: business_date, status: "completed")
    other_audit = create(:night_audit, status: "running")

    expect do
      described_class.call!(hotel: hotel, action: :review_due_out, night_audit: completed)
    end.to raise_error(described_class::OperationalChangeBlocked)

    expect do
      described_class.call!(hotel: hotel, action: :review_due_out, night_audit: other_audit)
    end.to raise_error(described_class::OperationalChangeBlocked)
  end
end
