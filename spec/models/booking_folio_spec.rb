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
        folio_type: "guest",
        payer_type: "guest",
        currency: "MYR",
        opened_at: Time.current
      )
    end

    let(:hotel_corporate_account) { create(:hotel_corporate_account, hotel: booking.hotel) }

    it { should validate_presence_of(:folio_number) }
    it "scopes folio number uniqueness by hotel and year" do
      existing = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_year: 2026, folio_number: 900)
      duplicate = build(:booking_folio, hotel: booking.hotel, booking: create(:booking, hotel: booking.hotel), folio_year: 2026, folio_number: 900)
      next_year = build(:booking_folio, hotel: booking.hotel, booking: create(:booking, hotel: booking.hotel), folio_year: 2027, folio_number: 900)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:folio_number]).to include("has already been taken")
      expect(next_year).to be_valid
      expect(existing).to be_persisted
    end
    it { should validate_presence_of(:status) }

    it "assigns required defaults" do
      folio = build(:booking_folio, label: nil, currency: nil, opened_at: nil)

      expect(folio).to be_valid
      expect(folio.label).to be_nil
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

    it "identifies a folio by its reference until a human labels it" do
      folio = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 391)

      expect(folio.label).to be_nil
      expect(folio.display_name).to eq(folio.folio_reference_display)
      expect(folio.display_option_label).to eq(folio.folio_reference_display)

      folio.update!(label: "Honeymoon extras")
      expect(folio.display_name).to eq("Honeymoon extras")
      expect(folio.display_option_label).to eq("Honeymoon extras · #{folio.folio_reference_display}")
      expect(folio.display_with_payer).to eq("Honeymoon extras · Guest")

      folio.update!(label: nil)
      expect(folio.display_name).to eq(folio.folio_reference_display)
    end

    it "accepts open, closed, and voided statuses" do
      expect(build(:booking_folio, status: "open")).to be_valid
      expect(build(:booking_folio, status: "closed")).to be_valid
      expect(build(:booking_folio, status: "voided")).to be_valid
      expect(build(:booking_folio, status: "reopened")).not_to be_valid
    end

    it "accepts OTA payer folios" do
      booking_source = create(:booking_source, kind: "ota")
      party = create(:booking_billing_party, booking: booking, hotel: booking.hotel, party_kind: "ota", booking_source: booking_source, hotel_corporate_account: nil)
      folio = build(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, payer_type: "ota", booking_billing_party: party)

      expect(folio).to be_valid
    end

    it "requires an OTA billing party for OTA payer folios" do
      folio = build(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, payer_type: "ota", booking_billing_party: nil)

      expect(folio).not_to be_valid
      expect(folio.errors[:booking_billing_party]).to include("must be an OTA billing party")
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

    it "blocks billing a guest-type folio to a company even via raw SQL" do
      guest = create(:booking_folio, folio_type: "guest", booking: booking, hotel: booking.hotel)

      expect do
        BookingFolio.where(id: guest.id).update_all(payer_type: "company")
      end.to raise_error(ActiveRecord::StatementInvalid, /booking_folios_guest_type_is_guest_payer/)
    end

    it "requires an active same-hotel Corporate Account for company payer folios" do
      missing = build(:booking_folio, folio_type: "external", payer_type: "company", hotel_corporate_account: nil)
      suspended = build(:booking_folio, folio_type: "external", payer_type: "company", hotel: booking.hotel, booking: booking, hotel_corporate_account: create(:hotel_corporate_account, hotel: booking.hotel, status: "suspended"))
      wrong_hotel = build(:booking_folio, folio_type: "external", payer_type: "company", hotel: booking.hotel, booking: booking, hotel_corporate_account: create(:hotel_corporate_account))

      expect(missing).not_to be_valid
      expect(missing.errors[:hotel_corporate_account]).to include("must be selected for Corporate Account folios")
      expect(suspended).not_to be_valid
      expect(suspended.errors[:hotel_corporate_account]).to include("must be active")
      expect(wrong_hotel).not_to be_valid
      expect(wrong_hotel.errors[:hotel_corporate_account]).to include("must belong to the folio hotel")
    end

    it "does not block unrelated edits to legacy company folios without a linked account" do
      folio = create(:booking_folio, folio_type: "external", payer_type: "agent")
      folio.update_columns(payer_type: "company", hotel_corporate_account_id: nil)

      expect(folio.update(label: "Legacy Company Folio")).to be(true)
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

    it "allows independent booking-level and room-level primary folios" do
      booking_primary = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 1)
      booking_room = create(:booking_room, booking: booking)
      room_primary = create(:booking_folio, hotel: booking.hotel, booking: booking, booking_room: booking_room, folio_number: 2)

      expect(booking_primary).to be_is_primary
      expect(room_primary).to be_is_primary
      expect(booking.reload.booking_folio).to eq(booking_primary)
    end

    it "allows primary folios for rooms on different group booking children" do
      group = create(:group_booking, hotel: booking.hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: booking.hotel, group_booking: group, group_position: 2)
      first_room = create(:booking_room, booking: booking)
      second_room = create(:booking_room, booking: sibling)

      first_primary = create(:booking_folio, hotel: booking.hotel, booking: booking, booking_room: first_room, folio_number: 1)
      second_primary = create(:booking_folio, hotel: booking.hotel, booking: sibling, booking_room: second_room, folio_number: 2)

      expect(first_primary).to be_valid
      expect(second_primary).to be_valid
    end

    it "rejects duplicate primary folios for the same room" do
      booking_room = create(:booking_room, booking: booking)
      create(:booking_folio, hotel: booking.hotel, booking: booking, booking_room: booking_room, folio_number: 1)

      duplicate = build(:booking_folio, hotel: booking.hotel, booking: booking, booking_room: booking_room, folio_number: 2)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:is_primary]).to include("has already been taken")
    end

    it "rejects a booking room from another booking" do
      other_room = create(:booking_room)
      folio = build(:booking_folio, :secondary, hotel: booking.hotel, booking: booking, booking_room: other_room)

      expect(folio).not_to be_valid
      expect(folio.errors[:booking_room]).to include("must belong to the same booking")
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

  describe "room scope" do
    let(:booking) { create(:booking) }
    let(:booking_room) { create(:booking_room, booking: booking) }
    let!(:booking_level_folio) { create(:booking_folio, booking: booking, hotel: booking.hotel) }
    let!(:room_folio) { create(:booking_folio, booking: booking, hotel: booking.hotel, booking_room: booking_room, folio_sequence: 2, is_primary: false) }

    it "separates room-scoped and booking-level folios" do
      expect(described_class.booking_level).to include(booking_level_folio)
      expect(described_class.booking_level).not_to include(room_folio)
      expect(described_class.room_scoped).to include(room_folio)
      expect(described_class.room_scoped).not_to include(booking_level_folio)
    end

    it "enforces the booking room foreign key" do
      expect {
        room_folio.update_column(:booking_room_id, -1)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "does not count a room primary as a replacement for the booking-level primary" do
      room_folio.update!(is_primary: true)

      expect(booking_level_folio.update(is_primary: false)).to be(false)
      expect(booking_level_folio.errors[:is_primary]).to include("must remain set until another primary folio exists in the same scope")
    end

    it "restricts deletion of a booking room with folios" do
      expect(booking_room.destroy).to be(false)
      expect(booking_room.errors[:base]).to include("Cannot delete record because dependent booking folios exist")
      expect { booking_room.delete }.to raise_error(ActiveRecord::StatementInvalid, /foreign key constraint/)
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

  describe "#reopening_for_correction" do
    let(:folio) { create(:booking_folio, status: "closed") }

    it "permits a reopen inside the block" do
      folio.reopening_for_correction { folio.update!(status: "open") }

      expect(folio.reload).to be_open
    end

    it "returns the block's value" do
      expect(folio.reopening_for_correction { :reopened }).to eq(:reopened)
    end

    it "yields the folio" do
      expect { |block| folio.reopening_for_correction(&block) }.to yield_with_args(folio)
    end

    it "withdraws the authorization once the block returns" do
      folio.reopening_for_correction { folio.update!(status: "open") }
      folio.update_column(:status, "closed")

      expect { folio.update!(status: "open") }.to raise_error(ActiveRecord::RecordInvalid, /controlled correction workflow/)
    end

    it "withdraws the authorization when the block raises" do
      expect {
        folio.reopening_for_correction { raise "boom" }
      }.to raise_error("boom")

      expect { folio.update!(status: "open") }.to raise_error(ActiveRecord::RecordInvalid, /controlled correction workflow/)
    end
  end
end
