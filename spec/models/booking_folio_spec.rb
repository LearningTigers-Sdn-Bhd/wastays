# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingFolio, type: :model do
  describe "associations" do
    it { should belong_to(:hotel) }
    it { should belong_to(:booking) }
  end

  describe "validations" do
    let(:booking) { create(:booking) }
    subject { BookingFolio.new(hotel: booking.hotel, booking: booking, folio_number: 123, status: "open") }

    it { should validate_presence_of(:folio_number) }
    it { should validate_uniqueness_of(:folio_number).scoped_to(:hotel_id) }
    it { should validate_presence_of(:status) }

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
  end
end
