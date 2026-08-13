# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingCorporateDraft do
  let(:hotel) { create(:hotel) }

  it "normalizes the email and defaults the currency to the property's" do
    draft = described_class.create!(hotel: hotel, email: "  Accounts@Acme.COM ", company_name: " Acme  ")

    expect(draft.email).to eq("accounts@acme.com")
    expect(draft.company_name).to eq("Acme")
    expect(draft.credit_currency).to eq(hotel.default_currency)
  end

  it "allows one draft per email per property" do
    create(:onboarding_corporate_draft, hotel: hotel, email: "accounts@acme.com")
    duplicate = build(:onboarding_corporate_draft, hotel: hotel, email: "ACCOUNTS@acme.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
  end

  # `invitations` has a unique index on (hotel_id, email) for anything unaccepted
  # that is not scoped by kind, so these collisions would otherwise only surface
  # at delivery — long after the owner could do anything about them.
  it "refuses an email with a pending invitation for the property" do
    create(:corporate_invitation, hotel: hotel, account: hotel.account, email: "accounts@acme.com")
    draft = build(:onboarding_corporate_draft, hotel: hotel, email: "accounts@acme.com")

    expect(draft).not_to be_valid
    expect(draft.errors[:email].to_sentence).to include("pending invitation")
  end

  it "refuses an email already queued as a staff member" do
    role = create(:role, account: hotel.account, slug: "front_desk")
    hotel.onboarding_staff_drafts.create!(email: "sam@acme.com", role: role, name: "Sam")
    draft = build(:onboarding_corporate_draft, hotel: hotel, email: "sam@acme.com")

    expect(draft).not_to be_valid
    expect(draft.errors[:email].to_sentence).to include("staff member")
  end

  it "knows whether submission has delivered it" do
    draft = create(:onboarding_corporate_draft, hotel: hotel, email: "accounts@acme.com")
    expect(draft).not_to be_delivered

    draft.update!(invitation: create(:corporate_invitation, hotel: hotel, account: hotel.account, email: "accounts@acme.com"),
                  delivered_at: Time.current)
    expect(draft).to be_delivered
    expect(described_class.undelivered).not_to include(draft)
  end
end
