# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingFolio, type: :model do
  it "prevents removal while night audit is running" do
    folio = create(:booking_folio)
    folio.hotel.current_business_date_record.update!(status: "audit_running")

    expect { folio.destroy }.to raise_error(NightAudits::OperationalChangeGuard::OperationalChangeBlocked)
    expect(described_class.exists?(folio.id)).to be(true)
  end

  describe "associations" do
    it { should belong_to(:hotel) }
    it { should belong_to(:booking) }
    it { should have_many(:folio_transactions).dependent(:restrict_with_error) }
  end

  describe "validations" do
    let(:booking) { create(:booking) }
    subject { BookingFolio.new(hotel: booking.hotel, booking: booking, folio_number: 123, status: "open") }

    it { should validate_presence_of(:folio_number) }
    it { should validate_uniqueness_of(:folio_number).scoped_to(:hotel_id) }
    it { should validate_presence_of(:status) }

    it "only accepts open and closed statuses" do
      expect(build(:booking_folio, status: "open")).to be_valid
      expect(build(:booking_folio, status: "closed")).to be_valid
      expect(build(:booking_folio, status: "reopened")).not_to be_valid
    end

    it "allows the same folio number for different hotels" do
      create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 1)
      other_booking = create(:booking)

      folio = build(:booking_folio, hotel: other_booking.hotel, booking: other_booking, folio_number: 1)

      expect(folio).to be_valid
    end

    it "rejects the same folio number within a hotel" do
      create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 1)
      other_booking = create(:booking, hotel: booking.hotel)

      folio = build(:booking_folio, hotel: booking.hotel, booking: other_booking, folio_number: 1)

      expect(folio).not_to be_valid
      expect(folio.errors[:folio_number]).to include("has already been taken")
    end

    it "rejects a hotel that does not match the booking hotel" do
      other_hotel = create(:hotel)

      folio = build(:booking_folio, hotel: other_hotel, booking: booking, folio_number: 1)

      expect(folio).not_to be_valid
      expect(folio.errors[:hotel]).to include("must match booking hotel")
    end
  end

  describe "#outstanding_balance" do
    it "returns 0.0" do
      folio = BookingFolio.new
      expect(folio.outstanding_balance).to eq(0.0)
    end

    it "calculates charges minus payments plus adjustments, including refunds as negative payments" do
      folio = create(:booking_folio)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 200.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "tax", amount: 20.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "gateway_payment", amount: 200.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "refund", amount: -40.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :adjustment, category: "discount", amount: -10.0)

      expect(folio.outstanding_balance).to eq(50.0)
    end
  end

  describe "#projected_forecasts" do
    it "excludes forecasts on or after the booking checkout date" do
      booking = create(:booking, status: "checked_in", check_in: Date.current, check_out: Date.current + 1.day)
      folio = create(:booking_folio, hotel: booking.hotel, booking: booking)
      included = create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current, identity: "included")
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current + 1.day, identity: "excluded")

      expect(folio.projected_forecasts).to contain_exactly(included)
    end

    it "excludes forecasts for closed or terminal lifecycle folios" do
      booking = create(:booking, status: "completed", check_in: Date.current, check_out: Date.current + 1.day)
      folio = create(:booking_folio, hotel: booking.hotel, booking: booking)
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current)

      expect(folio.projected_forecasts).to be_none

      booking.update_column(:status, "checked_in")
      folio.update!(status: "closed")

      expect(folio.projected_forecasts).to be_none
    end
  end

  describe "immutability interaction" do
    it "prevents destroying a folio with transactions" do
      folio = create(:booking_folio)
      create(:folio_transaction, booking_folio: folio)

      expect(folio.destroy).to be(false)
      expect(folio.errors[:base]).to include("Cannot delete record because dependent folio transactions exist")
      expect(described_class.exists?(folio.id)).to be(true)
    end
  end

  describe "database constraints" do
    it "rejects null statuses" do
      folio = create(:booking_folio)

      expect { folio.update_column(:status, nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects statuses outside the lifecycle" do
      folio = create(:booking_folio)

      expect { folio.update_column(:status, "reopened") }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "status transitions" do
    it "rejects direct reopening of a closed folio" do
      folio = create(:booking_folio, status: "closed")

      expect { folio.update!(status: "open") }.to raise_error(ActiveRecord::RecordInvalid, /controlled correction workflow/)
      expect(folio.reload).to be_closed
    end
  end
end
