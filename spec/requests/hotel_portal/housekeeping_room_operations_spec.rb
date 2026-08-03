# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel portal housekeeping room operations", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account:, status: "live", plan:) }
  let(:user) { create(:user, account:, role: "admin") }
  let(:role) { create(:role, account:, slug: "housekeeping-operator", name: "Housekeeping Operator") }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101]) }

  before do
    permission = Permission.find_or_create_by!(slug: "perform_housekeeping_tasks") { |record| record.name = "Perform housekeeping tasks" }
    RolePermission.create!(role:, permission:)
    UserHotelAccess.create!(user:, hotel:, role:)
    feature_group = create(:feature_group)
    feature = create(:feature, feature_group:, slug: "task_assignment_minibar_log")
    create(:plan_feature, plan:, feature:, enabled: true)
    sign_in_as(user)
  end

  it "updates room status without a housekeeping task" do
    room_status = create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")

    patch hotel_housekeeping_room_status_path(hotel, room_type_id: room_type.id, room_number: "101"),
          params: { date: hotel.current_business_date, status: "cleaning" }

    expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
    expect(room_status.reload.status).to eq("cleaning")
    expect(HousekeepingRequest.operational_tasks).to be_empty
  end

  it "moves a room from Cleaning to Cleaned when remarks exist" do
    room_status = create(
      :room_status, hotel:, room_type:, room_number: "101", status: "cleaning", notes: "Inspection complete"
    )

    patch hotel_housekeeping_room_status_path(hotel, room_type_id: room_type.id, room_number: "101"),
          params: { date: hotel.current_business_date, status: "ready" }

    expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
    expect(room_status.reload.status).to eq("ready")
  end

  it "rejects a historical status update" do
    room_status = create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")

    patch hotel_housekeeping_room_status_path(hotel, room_type_id: room_type.id, room_number: "101"),
          params: { date: hotel.current_business_date - 1.day, status: "cleaning" }

    expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
    expect(flash[:alert]).to eq("Housekeeping can only be updated for the current business date.")
    expect(room_status.reload.status).to eq("dirty")
  end

  it "does not let a performer assign a room" do
    patch hotel_housekeeping_room_assignment_path(hotel, room_type_id: room_type.id, room_number: "101"),
          params: { date: hotel.current_business_date, assigned_to_id: user.id }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
  end
end
