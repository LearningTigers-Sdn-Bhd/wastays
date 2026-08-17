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

    it "stores the structured cancellation tiers the guest is signing against" do
      hotel = create(:hotel)
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", cancellation_policy: "No refund after check-in")
      policy = create(:hotel_reservation_policy, :charging_cancellation, hotel: hotel, description: "Deposit transferable to a future stay.")
      create(:hotel_cancellation_policy_tier, hotel_reservation_policy: policy, days_before_arrival: 14, rate_value: 0)
      card = create(:guest_registration_card, hotel: hotel, booking: create(:booking, hotel: hotel))

      snapshot = card.capture_terms_snapshot!

      expect(snapshot["cancellation_policy_data"]["tiers"].first).to include("window" => "14+ days before arrival", "charge" => "No charge")
      expect(snapshot["cancellation_policy_data"]["description"]).to eq("Deposit transferable to a future stay.")
      # The flat text is generated from the same rows, never the retired prose.
      expect(snapshot["cancellation_policy"]).to include("14+ days before arrival: No charge")
      expect(snapshot["cancellation_policy"]).not_to include("No refund after check-in")
    end
  end

  describe "public_token" do
    it "is generated on create and never blank" do
      card = create(:guest_registration_card)

      expect(card.public_token).to be_present
      expect(card.public_token.length).to eq(40)
    end

    it "is not regenerated once assigned" do
      card = create(:guest_registration_card)
      original = card.public_token

      card.update!(display_fields_snapshot: %w[email])

      expect(card.reload.public_token).to eq(original)
    end
  end

  describe "#capture_terms_snapshot_preview" do
    it "freezes the hotel's fixed terms and conditions alongside the cancellation policy" do
      hotel = create(:hotel, guest_registration_card_terms: "Valid ID required at check-in.")
      card = create(:guest_registration_card, hotel: hotel, booking: create(:booking, hotel: hotel))

      snapshot = card.capture_terms_snapshot!

      expect(snapshot["terms_and_conditions"]).to eq("Valid ID required at check-in.")
    end

    it "omits the key when the hotel has not set one" do
      hotel = create(:hotel, guest_registration_card_terms: nil)
      card = create(:guest_registration_card, hotel: hotel, booking: create(:booking, hotel: hotel))

      expect(card.capture_terms_snapshot_preview).not_to have_key("terms_and_conditions")
    end

    it "keeps a signed card's terms unchanged after the hotel edits its policy" do
      hotel = create(:hotel, guest_registration_card_terms: "Original terms.")
      card = create(:guest_registration_card, :signed, hotel: hotel, booking: create(:booking, hotel: hotel))
      card.capture_terms_snapshot!

      hotel.update!(guest_registration_card_terms: "Updated terms.")

      expect(card.reload.terms_snapshot["terms_and_conditions"]).to eq("Original terms.")
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
