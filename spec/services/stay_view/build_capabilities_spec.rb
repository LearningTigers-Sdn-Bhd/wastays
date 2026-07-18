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

  def enable_housekeeping
    plan = create(:plan)
    hotel.update!(plan:)
    feature = create(:feature, slug: "task_assignment_minibar_log")
    create(:plan_feature, plan:, feature:, enabled: true)
    hotel.remove_instance_variable(:@plan_feature_map) if hotel.instance_variable_defined?(:@plan_feature_map)
  end

  it "maps existing hotel permissions to explicit capabilities" do
    enable_housekeeping
    grant(
      "view_bookings", "manage_bookings", "manage_guest_arrival", "manage_rates",
      "view_financial_status", "manage_room_status", "manage_housekeeping_tasks", "manage_requests"
    )

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).to be_view_board
    expect(capabilities).to be_view_booking
    expect(capabilities).to be_manage_bookings
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
    expect(capabilities).to be_update_housekeeping_status
    expect(capabilities).to be_manage_room_blocks
    expect(capabilities).to be_view_financial_status
  end

  it "requires booking visibility in addition to the financial permission" do
    grant("view_financial_status")

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).not_to be_view_board
    expect(capabilities).not_to be_view_booking
    expect(capabilities).not_to be_view_financial_status
  end

  it "keeps lifecycle mutations aligned with the manage bookings permission" do
    grant("manage_guest_arrival")

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).to be_check_in
    expect(capabilities).to be_check_out
    expect(capabilities).not_to be_manage_bookings
  end

  it "enables lifecycle mutations for booking managers" do
    grant("manage_bookings")

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).to be_manage_bookings
  end


  it "keeps housekeeping mutations disabled when the plan feature is unavailable" do
    grant("view_room_readiness", "manage_housekeeping_tasks", "manage_requests")

    capabilities = described_class.call(user:, hotel:)

    expect(capabilities).not_to be_manage_housekeeping
    expect(capabilities).not_to be_update_housekeeping_status
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

    expect(capabilities.to_h.values).to all(be(true))
  end
end
