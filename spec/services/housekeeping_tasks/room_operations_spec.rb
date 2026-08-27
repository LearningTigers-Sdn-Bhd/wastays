# frozen_string_literal: true

require "rails_helper"

RSpec.describe "room-centric housekeeping operations" do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }
  let(:business_date) { hotel.current_business_date }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", quantity: 1, room_numbers: %w[101]) }

  def grant(role, *slugs)
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
  end

  def user_with(*slugs, name: "Housekeeper")
    role = create(:role, account:, slug: "role-#{SecureRandom.hex(4)}", name:)
    grant(role, *slugs)
    create(:user, account:, name:).tap { |user| create(:user_hotel_access, user:, hotel:, role:) }
  end

  let(:performer) { user_with("perform_housekeeping_tasks") }
  let(:dispatcher) { user_with("dispatch_housekeeping_tasks", name: "Dispatcher") }

  describe HousekeepingTasks::UpdateRoomStatus do
    it "reports a passed due-out for the exact room and transitions its booking atomically" do
      other_type = create(:room_type, hotel:, room_number_mode: "custom", quantity: 1, room_numbers: %w[201])
      other_booking = create(:booking, hotel:, status: "checked_in", check_out: 2.hours.ago)
      create(:booking_room, booking: other_booking, room_type: other_type, room_number: "201")
      booking = create(:booking, hotel:, status: "checked_in", check_out: 1.hour.ago)
      create(:booking_room, booking:, room_type:, room_number: "101")
      room_status = create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")

      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
        status: "late_checkout_detected", notes: "Guest still in room", current_user: performer
      ).call

      expect(result).to be_success
      expect(room_status.reload.status).to eq("late_checkout_detected")
      expect(booking.reload.status).to eq("due_out_detected")
      expect(other_booking.reload.status).to eq("checked_in")
    end

    it "rejects late checkout before the scheduled checkout time" do
      booking = create(:booking, hotel:, status: "checked_in", check_out: 1.hour.from_now)
      create(:booking_room, booking:, room_type:, room_number: "101")
      room_status = create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")

      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
        status: "late_checkout_detected", notes: "Guest still in room", current_user: performer
      ).call

      expect(result).not_to be_success
      expect(result.error).to eq("Late checkout can only be reported after the scheduled checkout time.")
      expect(room_status.reload.status).to eq("dirty")
      expect(booking.reload.status).to eq("checked_in")
    end

    it "rejects changes for a non-current business date" do
      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date - 1.day,
        status: "dirty", notes: "Old board", current_user: performer
      ).call

      expect(result).not_to be_success
      expect(result.error).to eq("Housekeeping can only be updated for the current business date.")
    end

    it "uses existing remarks and clears assignment when a housekeeper marks the room Cleaned" do
      assigned = user_with("perform_housekeeping_tasks", name: "Assigned Housekeeper")
      room_status = create(
        :room_status, hotel:, room_type:, room_number: "101", status: "cleaning",
        notes: "Inspected by supervisor", assigned_to: assigned
      )

      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
        status: "ready", notes: nil, current_user: performer
      ).call

      expect(result).to be_success
      expect(room_status.reload).to have_attributes(status: "ready", assigned_to_id: nil, notes: "Inspected by supervisor")
    end
  end

  describe HousekeepingTasks::AssignRoom do
    it "allows only a dispatcher to assign an active housekeeper in this hotel" do
      housekeeper_role = create(:role, account:, slug: "housekeeper", name: "Housekeeper")
      grant(housekeeper_role, "perform_housekeeping_tasks")
      assignee = create(:user, account:, name: "Sam")
      create(:user_hotel_access, user: assignee, hotel:, role: housekeeper_role)

      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
        assigned_to_id: assignee.id, current_user: dispatcher
      ).call

      expect(result).to be_success
      expect(result.room_status.assigned_to).to eq(assignee)
      expect(RoomOperationalAuditLog.last.event_type).to eq("housekeeping_room_assignment_changed")

      expect {
        described_class.new(
          hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
          assigned_to_id: nil, current_user: performer
        ).call
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  describe HousekeepingTasks::UpdateRoomRemarks do
    it "allows a performer to write audited room remarks without a task" do
      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
        notes: "Guest requested extra linen", current_user: performer
      ).call

      expect(result).to be_success
      expect(result.room_status.notes).to eq("Guest requested extra linen")
      expect(RoomOperationalAuditLog.last).to have_attributes(
        event_type: "housekeeping_room_remarks_changed",
        reason: "Guest requested extra linen"
      )
    end

    it "clears existing remarks and preserves the previous value in the audit" do
      room_status = create(
        :room_status, hotel:, room_type:, room_number: "101", status: "dirty", notes: "Remove after inspection"
      )

      result = described_class.new(
        hotel:, room_type_id: room_type.id, room_number: "101", date: business_date,
        notes: "", current_user: performer
      ).call

      expect(result).to be_success
      expect(room_status.reload.notes).to be_nil
      expect(RoomOperationalAuditLog.last.metadata).to include("old_notes" => "Remove after inspection")
    end
  end
end
