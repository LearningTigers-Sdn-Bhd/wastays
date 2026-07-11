require "rails_helper"

RSpec.describe GuestRegistrationCard, type: :model do
  describe "validations" do
    it "allows one card per booking" do
      booking = create(:booking)
      create(:guest_registration_card, booking: booking, hotel: booking.hotel)

      duplicate = build(:guest_registration_card, booking: booking, hotel: booking.hotel)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:booking_id]).to include("has already been taken")
    end

    it "requires hotel to match booking hotel" do
      booking = create(:booking)
      other_hotel = create(:hotel)

      card = build(:guest_registration_card, booking: booking, hotel: other_hotel)

      expect(card).not_to be_valid
      expect(card.errors[:hotel]).to include("must match booking hotel")
    end

    it "requires signer name and signature data when signed" do
      card = build(:guest_registration_card, status: "signed", signer_name: "", signature_data_url: "")

      expect(card).not_to be_valid
      expect(card.errors[:signer_name]).to include("can't be blank")
      expect(card.errors[:signature_data_url]).to include("can't be blank")
    end
  end

  describe "#capture_terms_snapshot!" do
    it "stores current property policy terms" do
      hotel = create(:hotel)
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM", cancellation_policy: "No refund after check-in")
      card = create(:guest_registration_card, hotel: hotel, booking: create(:booking, hotel: hotel))

      snapshot = card.capture_terms_snapshot!

      expect(snapshot).to include(
        "check_in_time" => "3:00 PM",
        "check_out_time" => "11:00 AM",
        "cancellation_policy" => "No refund after check-in"
      )
      expect(card.reload.terms_snapshot).to eq(snapshot)
    end
  end

  describe "display fields" do
    it "uses every supported field by default" do
      card = build(:guest_registration_card)

      expect(card.visible_fields).to eq(GuestRegistrationCard::DISPLAY_FIELDS.keys)
    end

    it "uses sanitized hotel settings while draft" do
      hotel = create(:hotel, guest_registration_card_fields: %w[email room_type unknown])
      card = build(:guest_registration_card, hotel: hotel, booking: build(:booking, hotel: hotel))

      expect(card.visible_fields).to eq(%w[email room_type])
      expect(card.field_visible?(:room_type)).to be(true)
      expect(card.field_visible?(:phone)).to be(false)
    end

    it "uses its saved snapshot after signing" do
      hotel = create(:hotel, guest_registration_card_fields: %w[email room_type])
      card = build(:guest_registration_card, :signed, hotel: hotel, booking: build(:booking, hotel: hotel), display_fields_snapshot: %w[phone unknown])

      hotel.guest_registration_card_fields = %w[check_in]

      expect(card.visible_fields).to eq(%w[phone])
    end

    it "uses every supported field for a signed card with a nil snapshot" do
      card = build(:guest_registration_card, :signed, display_fields_snapshot: nil)

      expect(card.visible_fields).to eq(GuestRegistrationCard::DISPLAY_FIELDS.keys)
    end

    it "uses no fields for a signed card with an empty snapshot" do
      card = build(:guest_registration_card, :signed, display_fields_snapshot: [])

      expect(card.visible_fields).to eq([])
    end
  end
end
