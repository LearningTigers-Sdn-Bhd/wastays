# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::BuildCapabilities do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }

  def grant(*slugs)
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      create(:role_permission, role:, permission:)
    end
    create(:user_hotel_access, user:, hotel:, role:)
  end

  it "maps existing hotel permissions to explicit capabilities" do
    grant(
      "view_bookings", "manage_bookings", "manage_guest_arrival", "manage_rates",
      "manage_room_status", "manage_housekeeping_tasks"
    )

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).to be_view_board
    expect(capabilities).to be_view_booking
    expect(capabilities).to be_create_booking
    expect(capabilities).to be_move_booking
    expect(capabilities).to be_change_dates
    expect(capabilities).to be_reassign_room
    expect(capabilities).to be_check_in
    expect(capabilities).to be_check_out
    expect(capabilities).to be_view_rates
    expect(capabilities).to be_view_room_readiness
    expect(capabilities).to be_manage_room_status
    expect(capabilities).to be_manage_housekeeping
    expect(capabilities).to be_manage_room_blocks
    expect(capabilities).not_to be_view_financial_status
  end

  it "allows a readiness-only user to view a redacted board" do
    grant("view_room_readiness")

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).to be_view_board
    expect(capabilities).to be_view_room_readiness
    expect(capabilities).not_to be_view_booking
    expect(capabilities).not_to be_manage_room_status
  end

  it "grants superadmins all currently supported capabilities without querying hotel access" do
    superadmin = create(:user, :superadmin)

    capabilities = described_class.call(user: superadmin, hotel:)

    expect(capabilities.to_h.except(:view_financial_status).values).to all(be(true))
    expect(capabilities).not_to be_view_financial_status
  end
end
