# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinancialControls::PostingGuard do
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:business_date) { Date.current }
  let(:user) { create(:user, role: "superadmin") }

  def guard_call(**options)
    described_class.call!(
      hotel: hotel,
      business_date: business_date,
      actor: user,
      posting_source: "staff",
      **options
    )
  end

  it "allows normal posting on an open business date" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "open")

    expect(guard_call).to be(true)
  end

  it "blocks posting when the business-date control row is missing" do
    expect { guard_call }.to raise_error(described_class::PostingBlocked, /no accounting control record/)
  end

  it "allows night audit posting while audit is running" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_running")

    expect(guard_call(posting_source: "night_audit")).to be(true)
  end

  it "allows no-show posting while audit is running" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_running")

    expect(guard_call(posting_source: "no_show")).to be(true)
  end

  it "blocks normal posting while audit is running" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_running")

    expect { guard_call }.to raise_error(described_class::PostingBlocked, /currently in night audit/)
  end

  it "blocks normal posting while audit is blocked" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_blocked")

    expect { guard_call }.to raise_error(described_class::PostingBlocked, /blocked by night audit/)
  end

  it "allows blocker-resolution posting while audit is blocked" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_blocked")

    expect(
      guard_call(
        posting_source: "audit_blocker_resolution",
        override_reason: "Resolve captured payment blocker",
        blocker_resolution: { night_audit_id: 1, blocker_type: "captured_payment_not_synced" }
      )
    ).to be(true)
  end

  it "requires blocker context for audit-blocked resolution posting" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_blocked")

    expect do
      guard_call(posting_source: "audit_blocker_resolution", override_reason: "Resolve blocker")
    end.to raise_error(described_class::PostingBlocked, /Only audit blocker-resolution/)
  end

  it "blocks closed-date posting without override" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")

    expect { guard_call }.to raise_error(described_class::PostingBlocked, /closed/)
  end

  it "allows closed-date override with permission and reason" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")

    expect(guard_call(override: true, override_reason: "Approved correction")).to be(true)
  end

  it "requires permission for closed-date override" do
    regular_user = create(:user)
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")

    expect do
      described_class.call!(hotel: hotel, business_date: business_date, actor: regular_user, posting_source: "staff", override: true, override_reason: "Approved correction")
    end.to raise_error(described_class::PermissionRequired)
  end

  it "requires reason for closed-date override" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")

    expect { guard_call(override: true) }.to raise_error(described_class::OverrideReasonRequired)
  end

  it "blocks force-closed dates without override" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "force_closed")

    expect { guard_call }.to raise_error(described_class::PostingBlocked, /force-closed/)
  end

  it "allows force-closed date override with permission and reason" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "force_closed")

    expect(guard_call(override: true, override_reason: "Approved correction")).to be(true)
  end

  it "allows system-level override on a closed date without a user" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")

    expect(
      described_class.call!(
        hotel: hotel,
        business_date: business_date,
        actor: nil,
        posting_source: "sync",
        override: true,
        override_reason: "System sync"
      )
    ).to be(true)
  end
end
