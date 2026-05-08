# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("db/migrate/20260506000002_add_room_readiness_permissions.rb")

RSpec.describe AddRoomReadinessPermissions do
  it "creates room readiness permissions and assigns them to hotel roles" do
    account = create(:account)
    hotel_owner = create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner")
    general_manager = create(:role, account: account, slug: "general_manager", name: "General Manager")
    front_desk = create(:role, account: account, slug: "front_desk", name: "Front Desk")
    reservation_staff = create(:role, account: account, slug: "reservation_staff", name: "Reservation Staff")

    described_class.new.up

    expect(Permission.find_by!(slug: "view_room_readiness").name).to eq("View Room Readiness")
    expect(Permission.find_by!(slug: "manage_room_status").name).to eq("Manage Room Status")
    expect(Permission.find_by!(slug: "override_room_status_assignment").name).to eq("Override Room Status Assignment")

    expect(hotel_owner.permissions.pluck(:slug)).to include("view_room_readiness", "manage_room_status", "override_room_status_assignment")
    expect(general_manager.permissions.pluck(:slug)).to include("view_room_readiness", "manage_room_status", "override_room_status_assignment")
    expect(front_desk.permissions.pluck(:slug)).to eq([ "view_room_readiness" ])
    expect(reservation_staff.permissions.pluck(:slug)).to eq([ "view_room_readiness" ])
  end
end
