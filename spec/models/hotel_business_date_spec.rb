require "rails_helper"

RSpec.describe HotelBusinessDate, type: :model do
  subject(:business_date) { build(:hotel_business_date) }

  it { is_expected.to belong_to(:hotel) }
  it { is_expected.to validate_presence_of(:business_date) }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

  it "validates hotel/date uniqueness" do
    hotel = create(:hotel, :without_current_business_date)
    create(:hotel_business_date, hotel: hotel, business_date: Date.current)
    business_date.hotel = hotel
    business_date.business_date = Date.current

    expect(business_date).not_to be_valid
    expect(business_date.errors[:hotel_id]).to include("has already been taken")
  end

  it "defaults to open with an opened timestamp" do
    record = described_class.create!(hotel: create(:hotel, :without_current_business_date), business_date: Date.current)

    expect(record.status).to eq("open")
    expect(record.opened_at).to be_present
    expect(record.blockers_snapshot).to eq({})
  end

  describe ".for_hotel_date!" do
    it "creates an open business date" do
      hotel = create(:hotel, :without_current_business_date)
      date = Date.current

      record = described_class.for_hotel_date!(hotel: hotel, date: date)

      expect(record).to be_persisted
      expect(record.hotel).to eq(hotel)
      expect(record.business_date).to eq(date)
      expect(record).to be_open
      expect(record.opened_at).to be_present
    end

    it "returns an existing business date" do
      existing = create(:hotel_business_date, business_date: Date.current)

      record = described_class.for_hotel_date!(hotel: existing.hotel, date: existing.business_date)

      expect(record).to eq(existing)
    end
  end

  it "defines current and closed-like statuses without reopened" do
    expect(described_class::CURRENT_STATUSES).to eq(%w[open audit_running audit_blocked])
    expect(described_class::CLOSED_STATUSES).to eq(%w[closed force_closed])
    expect(described_class::STATUSES).not_to include("reopened")
  end

  it "enforces one current accounting business date per hotel at the database level" do
    hotel = create(:hotel, :without_current_business_date)
    create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_blocked")

    expect do
      described_class.insert_all!([
        { hotel_id: hotel.id, business_date: Date.current + 1.day, status: "open", blockers_snapshot: {}, created_at: Time.current, updated_at: Time.current }
      ])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows multiple closed-like dates for one hotel" do
    hotel = create(:hotel, :without_current_business_date)

    expect do
      create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "closed")
      create(:hotel_business_date, hotel: hotel, business_date: Date.current + 1.day, status: "force_closed")
    end.not_to raise_error
  end

  it "prevents direct destruction of the hotel's only current business date" do
    record = create(:hotel).current_business_date_record

    expect(record.destroy).to be(false)
    expect(record.errors[:base]).to include("cannot destroy the hotel's only current accounting business date")
    expect(record.reload).to be_persisted
  end

  it "allows current business dates to be destroyed with their hotel" do
    hotel = create(:hotel)

    expect { hotel.destroy! }.to change(described_class, :count).by(-1)
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

  it "exposes current, closed-like, blocker-resolution, and staff-operation helpers" do
    expect(build(:hotel_business_date, status: "audit_blocked")).to be_current
    expect(build(:hotel_business_date, status: "force_closed")).to be_closed_like
    expect(build(:hotel_business_date, status: "audit_blocked")).to be_allows_blocker_resolution
    expect(build(:hotel_business_date, status: "open")).to be_open_for_staff_operations
  end
end
