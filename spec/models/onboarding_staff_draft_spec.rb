# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingStaffDraft, type: :model do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:preset_role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }

  it "normalizes a valid preset staff draft" do
    draft = described_class.create!(hotel: hotel, role: preset_role, name: "  Ari  ", email: " ARI@Example.com ")

    expect(draft).to have_attributes(name: "Ari", email: "ari@example.com")
  end

  it "rejects roles from another account" do
    draft = described_class.new(hotel: hotel, role: create(:role, slug: "housekeeper"), email: "ari@example.com")

    expect(draft).not_to be_valid
    expect(draft.errors[:role]).to include("must belong to the property's account")
  end

  it "enforces case-insensitive email uniqueness per property" do
    described_class.create!(hotel: hotel, role: preset_role, email: "ari@example.com")
    duplicate = described_class.new(hotel: hotel, role: preset_role, email: "ARI@example.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to include("has already been taken")
  end
end
