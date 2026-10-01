require "rails_helper"

RSpec.describe Onboarding::DeliveryRecipients do
  let(:hotel) { create(:hotel) }

  it "deduplicates superadmins and excludes generated salesperson addresses" do
    superadmin = create(:user, :superadmin, email: "ops@example.com")
    hotel.update!(salesperson: superadmin)

    expect(described_class.admins_for(hotel)).to eq([ "ops@example.com" ])

    hotel.update!(salesperson: create(:user, email: "generated@salesperson.local"))
    expect(described_class.admins_for(hotel)).to eq([ "ops@example.com" ])
  end

  it "includes a deliverable assigned salesperson address" do
    salesperson = create(:user, email: "sales@example.com")
    hotel.update!(salesperson:)

    expect(described_class.admins_for(hotel)).to include("sales@example.com")
  end

  it "returns every active hotel owner once" do
    owner_role = create(:role, account: hotel.account, slug: "hotel_owner")
    owner = create(:user, account: hotel.account, email: "owner@example.com")
    create(:user_hotel_access, hotel:, user: owner, role: owner_role)
    create(:user_hotel_access, hotel:, user: create(:user, account: hotel.account), role: create(:role, account: hotel.account))

    expect(described_class.owners_for(hotel)).to eq([ "owner@example.com" ])
  end
end
