require "rails_helper"

RSpec.describe HotelBusinessDate, type: :model do
  subject(:business_date) { build(:hotel_business_date) }

  it { is_expected.to belong_to(:hotel) }
  it { is_expected.to validate_presence_of(:business_date) }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

  it "validates hotel/date uniqueness" do
    hotel = create(:hotel)
    create(:hotel_business_date, hotel: hotel, business_date: Date.current)
    business_date.hotel = hotel
    business_date.business_date = Date.current

    expect(business_date).not_to be_valid
    expect(business_date.errors[:hotel_id]).to include("has already been taken")
  end

  it "defaults to open with an opened timestamp" do
    record = described_class.create!(hotel: create(:hotel), business_date: Date.current)

    expect(record.status).to eq("open")
    expect(record.opened_at).to be_present
    expect(record.blockers_snapshot).to eq({})
  end

  it "transitions from open to audit_running" do
    record = create(:hotel_business_date, status: "open")

    record.start_audit!

    expect(record.status).to eq("audit_running")
    expect(record.audit_started_at).to be_present
  end

  it "transitions from audit_blocked to audit_running for retry" do
    record = create(:hotel_business_date, status: "audit_blocked", blockers_snapshot: { "x" => [ "y" ] }, blocked_at: Time.current)

    record.retry_audit!

    expect(record.status).to eq("audit_running")
    expect(record.blockers_snapshot).to eq({})
    expect(record.blocked_at).to be_nil
  end

  it "transitions from audit_running to audit_blocked with blocker details" do
    record = create(:hotel_business_date, status: "audit_running")
    blockers = { "due_out_not_checked_out" => [ { "booking_id" => 1 } ] }

    record.block_audit!(blockers: blockers)

    expect(record.status).to eq("audit_blocked")
    expect(record.blockers_snapshot).to eq(blockers)
    expect(record.blocked_at).to be_present
  end

  it "transitions from audit_running to closed" do
    record = create(:hotel_business_date, status: "audit_running", blockers_snapshot: { "x" => [ "y" ] }, blocked_at: Time.current)

    record.complete_audit!

    expect(record.status).to eq("closed")
    expect(record.closed_at).to be_present
    expect(record.blockers_snapshot).to eq({})
    expect(record.blocked_at).to be_nil
  end

  it "rejects invalid transitions" do
    record = create(:hotel_business_date, status: "closed")

    expect { record.start_audit! }.to raise_error(described_class::InvalidTransition)
  end

  it "allows normal postings only when open" do
    expect(build(:hotel_business_date, status: "open")).to be_normal_posting_allowed
    expect(build(:hotel_business_date, status: "audit_running")).not_to be_normal_posting_allowed
    expect(build(:hotel_business_date, status: "audit_blocked")).not_to be_normal_posting_allowed
    expect(build(:hotel_business_date, status: "closed")).not_to be_normal_posting_allowed
  end

  it "allows audit postings only when audit_running" do
    expect(build(:hotel_business_date, status: "audit_running")).to be_audit_posting_allowed
    expect(build(:hotel_business_date, status: "open")).not_to be_audit_posting_allowed
  end
end
