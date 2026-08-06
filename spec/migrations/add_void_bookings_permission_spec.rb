# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("db/migrate/20260727100000_add_void_bookings_permission.rb")

RSpec.describe AddVoidBookingsPermission do
  it "assigns void access only to hotel owners and general managers" do
    account = create(:account)
    hotel_owner = create(:role, account:, slug: "hotel_owner", name: "Hotel Owner")
    general_manager = create(:role, account:, slug: "general_manager", name: "General Manager")
    front_desk = create(:role, account:, slug: "front_desk", name: "Front Desk")

    described_class.new.up

    expect(Permission.find_by!(slug: "void_bookings").name).to eq("Void Bookings")
    expect(hotel_owner.permissions.pluck(:slug)).to include("void_bookings")
    expect(general_manager.permissions.pluck(:slug)).to include("void_bookings")
    expect(front_desk.permissions.pluck(:slug)).not_to include("void_bookings")
  end
end
