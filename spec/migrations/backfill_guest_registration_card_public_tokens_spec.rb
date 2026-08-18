# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("db/migrate/20260817160000_backfill_guest_registration_card_public_tokens.rb")

RSpec.describe BackfillGuestRegistrationCardPublicTokens do
  it "assigns a unique token to every card left without one" do
    card = create(:guest_registration_card)
    card.update_column(:public_token, nil)
    other_card = create(:guest_registration_card)
    other_card.update_column(:public_token, nil)
    untouched = create(:guest_registration_card)
    untouched_token = untouched.public_token

    described_class.new.up

    expect(card.reload.public_token).to be_present
    expect(other_card.reload.public_token).to be_present
    expect(card.reload.public_token).not_to eq(other_card.reload.public_token)
    expect(untouched.reload.public_token).to eq(untouched_token)
  end
end
