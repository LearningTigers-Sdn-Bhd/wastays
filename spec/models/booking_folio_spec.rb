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
    subject do
      BookingFolio.new(
        hotel: booking.hotel,
        booking: booking,
        folio_number: 123,
        status: "open",
        name: "Guest Folio",
        folio_type: "guest",
        payer_type: "guest",
        currency: "MYR",
        opened_at: Time.current
      )
    end

    let(:hotel_corporate_account) { create(:hotel_corporate_account, hotel: booking.hotel) }

    it { should validate_presence_of(:folio_number) }
    it { should validate_uniqueness_of(:folio_number).scoped_to(:hotel_id) }
    it { should validate_presence_of(:status) }

    it "assigns required defaults" do
      folio = build(:booking_folio, name: nil, currency: nil, opened_at: nil)

      expect(folio).to be_valid
      expect(folio.name).to eq("Guest Folio")
      expect(folio.currency).to eq("MYR")
      expect(folio.opened_at).to be_present
      expect(folio.folio_sequence).to eq(1)
    end

    it "assigns stable account and derived folio references" do
      primary = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 381)
      secondary = create(:booking_folio, :secondary, hotel: booking.hotel, booking: booking, folio_number: 382)

      account_reference = booking.reload.folio_account_reference_display

      expect(account_reference).to eq(booking.formatted_folio_number)
      expect(primary.reload.folio_sequence).to eq(1)
      expect(secondary.reload.folio_sequence).to eq(2)
      expect(primary.folio_reference_display).to eq("#{account_reference}/1")
      expect(secondary.folio_reference_display).to eq("#{account_reference}/2")
    end

    it "accepts open, closed, and voided statuses" do
      expect(build(:booking_folio, status: "open")).to be_valid
      expect(build(:booking_folio, status: "closed")).to be_valid
      expect(build(:booking_folio, status: "voided")).to be_valid
      expect(build(:booking_folio, status: "reopened")).not_to be_valid
    end

    it "accepts the supported folio window and payer types" do
      expect(build(:booking_folio, folio_type: "guest", payer_type: "guest")).to be_valid
      expect(build(:booking_folio, folio_type: "external", payer_type: "company", hotel_corporate_account: hotel_corporate_account, hotel: booking.hotel, booking: booking)).to be_valid
      expect(build(:booking_folio, folio_type: "external", payer_type: "agent")).to be_valid
      expect(build(:booking_folio, folio_type: "external", payer_type: "hotel")).to be_valid
      expect(build(:booking_folio, folio_type: "external", payer_type: "custom")).to be_valid
      expect(build(:booking_folio, folio_type: "house", payer_type: "hotel")).to be_valid
    end

    it "rejects retired folio window types" do
      expect(build(:booking_folio, folio_type: "company")).not_to be_valid
      expect(build(:booking_folio, folio_type: "custom")).not_to be_valid
      expect(build(:booking_folio, folio_type: "group")).not_to be_valid
      expect(build(:booking_folio, folio_type: "master")).not_to be_valid
    end

    it "normalizes locked payer types" do
      guest_folio = build(:booking_folio, folio_type: "guest", payer_type: "company", hotel_corporate_account: hotel_corporate_account)
      house_folio = build(:booking_folio, folio_type: "house", payer_type: "custom")

      expect(guest_folio).to be_valid
      expect(guest_folio.payer_type).to eq("guest")
      expect(guest_folio.hotel_corporate_account).to be_nil
      expect(house_folio).to be_valid
      expect(house_folio.payer_type).to eq("hotel")
    end

    it "requires an active same-hotel Company & Government account for company payer folios" do
      missing = build(:booking_folio, folio_type: "external", payer_type: "company", hotel_corporate_account: nil)
      suspended = build(:booking_folio, folio_type: "external", payer_type: "company", hotel: booking.hotel, booking: booking, hotel_corporate_account: create(:hotel_corporate_account, hotel: booking.hotel, status: "suspended"))
      wrong_hotel = build(:booking_folio, folio_type: "external", payer_type: "company", hotel: booking.hotel, booking: booking, hotel_corporate_account: create(:hotel_corporate_account))

      expect(missing).not_to be_valid
      expect(missing.errors[:hotel_corporate_account]).to include("must be selected for Company & Government folios")
      expect(suspended).not_to be_valid
      expect(suspended.errors[:hotel_corporate_account]).to include("must be active")
      expect(wrong_hotel).not_to be_valid
      expect(wrong_hotel.errors[:hotel_corporate_account]).to include("must belong to the folio hotel")
    end

    it "does not block unrelated edits to legacy company folios without a linked account" do
      folio = create(:booking_folio, folio_type: "external", payer_type: "agent")
      folio.update_columns(payer_type: "company", hotel_corporate_account_id: nil)

      expect(folio.update(name: "Legacy Company Folio")).to be(true)
    end

    it "allows multiple folios for the same booking when only one is primary" do
      primary = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 1)
      secondary = build(:booking_folio, :secondary, hotel: booking.hotel, booking: booking, folio_number: 2)

      expect(primary).to be_is_primary
      expect(secondary).to be_valid
    end

    it "rejects multiple primary folios for the same booking" do
      create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 1)
      duplicate_primary = build(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 2)

      expect(duplicate_primary).not_to be_valid
      expect(duplicate_primary.errors[:is_primary]).to include("has already been taken")
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

    it "rejects folio and payer types outside the allowed sets" do
      folio = create(:booking_folio)

      expect { folio.update_column(:folio_type, "company") }.to raise_error(ActiveRecord::StatementInvalid)
      expect { folio.update_column(:payer_type, "owner") }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "destroy protections" do
    it "prevents deleting the last folio for a booking" do
      folio = create(:booking_folio)

      expect(folio.destroy).to be(false)
      expect(folio.errors[:base]).to include("Cannot delete the last folio for a booking.")
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
