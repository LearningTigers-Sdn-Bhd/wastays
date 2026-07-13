# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentIdentifiers::HotelReferences do
  describe ".assign_confirmation_token" do
    it "assigns a token when the attribute is blank" do
      booking = build(:booking, confirmation_token: nil)

      described_class.assign_confirmation_token(booking)

      expect(booking.confirmation_token).to match(/\A[A-HJ-NP-Z2-9]{6}\z/)
    end

    it "does not overwrite an existing token" do
      booking = build(:booking, confirmation_token: "ABC234")

      described_class.assign_confirmation_token(booking)

      expect(booking.confirmation_token).to eq("ABC234")
    end

    it "retries when the generated token already exists" do
      booking = build(:booking, confirmation_token: nil)
      existing_scope = class_double(Booking)
      allow(existing_scope).to receive(:exists?).with(confirmation_token: "AAAAAA").and_return(true)
      allow(existing_scope).to receive(:exists?).with(confirmation_token: "BBBBBB").and_return(false)
      charset = double("token charset")
      stub_const("DocumentIdentifiers::HotelReferences::TOKEN_CHARSET", charset)
      allow(charset).to receive(:sample).and_return("A", "A", "A", "A", "A", "A", "B", "B", "B", "B", "B", "B")

      described_class.assign_confirmation_token(booking, unique_against: existing_scope)

      expect(booking.confirmation_token).to eq("BBBBBB")
    end
  end

  describe ".assign_counter" do
    it "assigns the next hotel counter when the attribute is blank" do
      booking = create(:booking, reservation_number: nil)

      described_class.assign_counter(booking, attribute: :reservation_number, counter_type: "reservation")

      expect(booking.reservation_number).to eq(1)
    end

    it "does not assign a counter without a hotel" do
      booking = OpenStruct.new(hotel: nil, reservation_number: nil)

      described_class.assign_counter(booking, attribute: :reservation_number, counter_type: "reservation")

      expect(booking.reservation_number).to be_nil
    end

    it "does not overwrite an existing counter" do
      booking = build(:booking, reservation_number: 42)

      described_class.assign_counter(booking, attribute: :reservation_number, counter_type: "reservation")

      expect(booking.reservation_number).to eq(42)
    end
  end

  describe ".format" do
    it "formats a hotel-prefixed document number" do
      hotel = build(:hotel, hotel_prefix: "HTL")

      expect(described_class.format(hotel: hotel, number: 12, type_code: "R")).to eq("HTL-R0000012")
    end

    it "falls back to the Wastays prefix" do
      hotel = build(:hotel, hotel_prefix: nil)

      expect(described_class.format(hotel: hotel, number: 3, type_code: "F")).to eq("WS-F0000003")
    end
  end
end
