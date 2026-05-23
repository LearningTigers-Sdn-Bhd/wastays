require "rails_helper"

RSpec.describe NightAudit, type: :model do
  subject(:night_audit) { build(:night_audit) }

  it { is_expected.to belong_to(:hotel) }
  it { is_expected.to belong_to(:performed_by_user).class_name("User").optional }

  it { is_expected.to validate_presence_of(:business_date) }
  it { is_expected.to validate_inclusion_of(:status).in_array(NightAudit::STATUSES) }
  it { is_expected.to validate_inclusion_of(:trigger_mode).in_array(NightAudit::TRIGGER_MODES) }

  it "defaults blocked_details to an empty hash" do
    expect(night_audit.blocked_details).to eq({})
  end

  it "validates hotel/date uniqueness" do
    hotel = create(:hotel)
    create(:night_audit, hotel: hotel, business_date: night_audit.business_date)
    night_audit.hotel = hotel

    expect(night_audit).not_to be_valid
    expect(night_audit.errors[:hotel_id]).to include("has already been taken")
  end

  it "orders recent audits first" do
    older = create(:night_audit, business_date: Date.current - 2.days)
    newer = create(:night_audit, business_date: Date.current)

    expect(described_class.recent_first.first).to eq(newer)
    expect(described_class.recent_first.last).to eq(older)
  end

  describe ".closed_for_date?" do
    it "uses hotel business dates as the closed-date source of truth" do
      hotel = create(:hotel)
      create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "closed")

      expect(described_class.closed_for_date?(hotel.id, Date.current)).to be(true)
    end

    it "falls back to completed night audits when no hotel business date exists" do
      night_audit = create(:night_audit, status: "completed")

      expect(described_class.closed_for_date?(night_audit.hotel_id, night_audit.business_date)).to be(true)
    end
  end
end
