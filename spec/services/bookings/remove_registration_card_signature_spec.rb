# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RemoveRegistrationCardSignature do
  describe ".call" do
    it "resets signature-related attributes and sets status to draft" do
      card = create(
        :guest_registration_card,
        :signed,
        display_fields_snapshot: { "guest_name" => "Jane Guest" }
      )

      expect(card.status).to eq("signed")
      expect(card.signer_name).to eq("Jane Guest")
      expect(card.signature_data_url).to eq("data:image/png;base64,abc123")
      expect(card.signed_at).not_to be_nil
      expect(card.display_fields_snapshot).not_to be_nil

      described_class.call(card: card)

      card.reload
      expect(card.status).to eq("draft")
      expect(card.signer_name).to be_nil
      expect(card.signature_data_url).to be_nil
      expect(card.signed_at).to be_nil
      expect(card.display_fields_snapshot).to be_nil
    end
  end
end
