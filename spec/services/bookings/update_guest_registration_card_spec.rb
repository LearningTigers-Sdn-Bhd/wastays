# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateGuestRegistrationCard do
  let(:booking) { create(:booking, hotel: hotel) }
  let(:hotel) { create(:hotel, guest_registration_card_terms: "Valid photo ID is required at check-in.") }
  let!(:property_policy) { create(:property_policy, hotel: hotel) }
  let(:card) { create(:guest_registration_card, booking: booking, hotel: hotel, status: "draft") }

  describe ".call" do
    context "when updating booking attributes only" do
      it "updates the booking special requests and internal notes" do
        params = {
          special_requests: "Need extra towels",
          internal_notes: "VIP guest"
        }

        result = described_class.call(card: card, booking: booking, params: params)

        expect(result.success?).to be true
        expect(booking.reload.special_requests).to eq("Need extra towels")
        expect(booking.internal_notes).to eq("VIP guest")
        expect(card.reload.status).to eq("draft")
      end
    end

    context "when signing the card" do
      it "successfully updates card status to signed and captures snapshots" do
        params = {
          signer_name: "John Doe",
          signature_data_url: "data:image/png;base64,signature123"
        }

        result = described_class.call(card: card, booking: booking, params: params)

        expect(result.success?).to be true
        card.reload
        expect(card.status).to eq("signed")
        expect(card.signer_name).to eq("John Doe")
        expect(card.signature_data_url).to eq("data:image/png;base64,signature123")
        expect(card.signed_at).not_to be_nil
        expect(card.terms_snapshot).to be_present
        expect(card.display_fields_snapshot).to be_present
      end

      it "returns invalid when signature_data_url is blank" do
        params = {
          signer_name: "John Doe",
          signature_data_url: ""
        }

        result = described_class.call(card: card, booking: booking, params: params)

        expect(result.success?).to be false
        expect(result.error).to eq(:invalid)
        expect(result.message).to include("Signature data url can't be blank")
        expect(card.reload.status).to eq("draft")
      end

      it "returns terms_missing when the hotel has not set its Terms & Conditions" do
        hotel.update!(guest_registration_card_terms: nil)
        params = {
          signer_name: "John Doe",
          signature_data_url: "data:image/png;base64,signature123"
        }

        result = described_class.call(card: card, booking: booking, params: params)

        expect(result.success?).to be false
        expect(result.error).to eq(:terms_missing)
        expect(card.reload.status).to eq("draft")
      end

      it "returns already_signed when card is already signed" do
        card.update!(status: "signed", signer_name: "Jane", signature_data_url: "data:abc")
        params = {
          signer_name: "John Doe",
          signature_data_url: "data:image/png;base64,signature123"
        }

        result = described_class.call(card: card, booking: booking, params: params)

        expect(result.success?).to be false
        expect(result.error).to eq(:already_signed)
        expect(result.message).to eq("Delete the existing signature before signing again.")
      end
    end
  end
end
