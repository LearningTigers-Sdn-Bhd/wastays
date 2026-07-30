# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adding a task to a room from the housekeeping board", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin", name: "Dana Dispatch") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Ocean Suite", room_number_mode: "custom", room_numbers: %w[101 202]) }

  def grant(*slugs)
    RolePermission.where(role: role).destroy_all
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
      RolePermission.create!(role: role, permission: permission)
    end
  end

  before do
    grant("dispatch_housekeeping_tasks", "perform_housekeeping_tasks")
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  def dirty_room(room_number = "101")
    create(:room_status, hotel: hotel, room_type: room_type, room_number: room_number, status: "dirty")
  end

  # Only a user on a "housekeeper" role is assignable, per ActiveHousekeepersQuery.
  def housekeeper(name)
    hk_role = Role.find_or_create_by!(account: account, slug: "housekeeper") { |record| record.name = "Housekeeper" }
    permission = Permission.find_or_create_by!(slug: "perform_housekeeping_tasks") { |record| record.name = "Perform" }
    RolePermission.find_or_create_by!(role: hk_role, permission: permission)

    create(:user, account: account, name: name).tap do |staff|
      UserRole.create!(user: staff, role: hk_role)
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
    end
  end

  def sheet_path(**overrides)
    hotel_housekeeping_action_new_task_path(hotel, { room_type_id: room_type.id, room_number: "101" }.merge(overrides))
  end

  describe "the board's offer" do
    it "offers a dispatcher the action on a dirty room with nothing asked of it" do
      dirty_room

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Add task")
      expect(response.body).to include("Add a task for Ocean Suite 101")
    end

    it "says nothing of it on a room that already has work" do
      dirty_room
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, hotel: hotel, room_number: "101", status: "new",
                                    request_details: "Towels", requested_at: Time.current)

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).not_to include("Add a task for Ocean Suite 101")
    end

    it "says nothing of it on a room that is not dirty" do
      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).not_to include("Add a task for")
    end

    it "says nothing of it to a housekeeper, who does not hand work out" do
      dirty_room
      grant("perform_housekeeping_tasks")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).not_to include("Add a task for")
    end
  end

  describe "the sheet" do
    it "renders into the housekeeping sheet frame, naming the room" do
      dirty_room

      get sheet_path, headers: { "Turbo-Frame" => "housekeeping_action_sheet" }

      expect(response).to have_http_status(:ok)
      # Turbo discards a frame response that does not carry the frame it asked
      # for, so the wrapper is the whole point of the reply.
      expect(response.body).to include('<turbo-frame id="housekeeping_action_sheet">')
      expect(response.body).to include("Add housekeeping task", "Ocean Suite 101")
      expect(response.body).to include("Assign later")
      expect(response.body).to include("housekeeping-task-sheet")
    end

    it "answers into a stacked frame when a stacked frame asked" do
      dirty_room

      get sheet_path, headers: { "Turbo-Frame" => "housekeeping_action_sheet_secondary" }

      expect(response.body).to include('<turbo-frame id="housekeeping_action_sheet_secondary">')
    end

    it "re-renders into the frame when the task is unnamed, so the sheet survives" do
      dirty_room

      post sheet_path, params: { request_details: "" }, headers: { "Turbo-Frame" => "housekeeping_action_sheet" }

      expect(response.body).to include('<turbo-frame id="housekeeping_action_sheet">')
      expect(response.body).to include("Enter what needs doing.")
    end

    it "turns a housekeeper away" do
      dirty_room
      grant("perform_housekeeping_tasks")

      get sheet_path

      expect(response).to redirect_to(root_path)
    end

    it "refuses a room number the room type does not have" do
      get sheet_path(room_number: "999")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "adding the task" do
    it "adds an unassigned task to the room and shows it on the board" do
      dirty_room

      expect { post sheet_path, params: { request_details: "Full clean", return_to: hotel_housekeeping_tasks_path(hotel, q: "101") } }
        .to change(HousekeepingRequest, :count).by(1)

      task = HousekeepingRequest.sole
      expect(task).to have_attributes(
        hotel_id: hotel.id, room_type_id: room_type.id, room_number: "101",
        request_details: "Full clean", status: "new", booking_id: nil
      )
      expect(task.requested_at).to be_present
      expect(task.metadata).to include("source" => "housekeeping_board", "created_by_name" => "Dana Dispatch")
      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel, q: "101"))

      get hotel_housekeeping_tasks_path(hotel)
      expect(response.body).to include("Full clean")
    end

    it "hands it straight to a housekeeper when one was picked" do
      dirty_room
      sam = housekeeper("Sam Lee")

      post sheet_path, params: { request_details: "Linen change", assigned_to: sam.id }

      task = HousekeepingRequest.sole
      expect(task.status).to eq("assigned")
      expect(task.metadata).to include("assigned_to" => sam.id, "assigned_to_name" => "Sam Lee")
      expect(task.metadata["assignment_history"].last).to include("assigned_by_name" => "Dana Dispatch")
      expect(RoomOperationalAuditLog.where(hotel: hotel, event_type: "housekeeping_assignment_changed")).to exist
    end

    it "re-renders the sheet, keeping the room, when the task is unnamed" do
      dirty_room

      expect { post sheet_path, params: { request_details: "  " } }.not_to change(HousekeepingRequest, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter what needs doing.", "Ocean Suite 101")
    end

    it "refuses a room that is not waiting for a task" do
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "cleaning")

      expect { post sheet_path, params: { request_details: "Full clean" } }.not_to change(HousekeepingRequest, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("not waiting for a task")
    end

    it "turns a housekeeper away" do
      dirty_room
      grant("perform_housekeeping_tasks")

      expect { post sheet_path, params: { request_details: "Full clean" } }.not_to change(HousekeepingRequest, :count)

      expect(response).to redirect_to(root_path)
    end

    it "keeps a crafted return_to from bouncing the operator off the property" do
      dirty_room

      post sheet_path, params: { request_details: "Full clean", return_to: "https://evil.example.com/steal" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
    end
  end
end
