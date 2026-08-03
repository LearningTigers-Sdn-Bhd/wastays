# frozen_string_literal: true

module HousekeepingTasks
  # What assigning means to one operational housekeeping task the board can hand out.
  class TaskAssignment
    RULES = {
      HousekeepingRequest: {
        # "no_task" is a record standing in for a room with nothing to ask for.
        # Taking it is how work starts on such a room, so assigning moves it on.
        assign_from: %w[new no_task pending],
        release_to_new_from: %w[assigned],
        mirrors_workflow_status: false,
        placeholder_statuses: %w[no_task]
      }
    }.freeze

    def self.wrap(records)
      records.map { |record| new(record) }
    end

    attr_reader :record

    def initialize(record)
      @record = record
    end

    # A record standing in for the absence of work. It is still assignable -- it
    # is how a room with nothing asked of it gets picked up -- but a room that
    # has real work does not need it moved as well.
    def placeholder?
      record.status.in?(rules[:placeholder_statuses])
    end

    def assigned_to
      record.metadata.to_h["assigned_to"]
    end

    def held_by_somebody_else?(user)
      assigned_to.present? && assigned_to != user.id
    end

    # Hands the task to staff, or back to nobody when staff is nil. Returns
    # whether that changed who holds it.
    def hand_over(staff, by:)
      held_before = assigned_to
      metadata = record.metadata.to_h
      status = record.status

      if staff
        note_history(metadata, by: by, to_id: staff.id, to_name: staff.name) if held_before != staff.id
        metadata["assigned_to"] = staff.id
        metadata["assigned_to_name"] = staff.name
        status = "assigned" if status.in?(rules[:assign_from])
        workflow_status = "assigned"
      else
        note_history(metadata, by: by, to_name: "Unassigned") if held_before.present?
        metadata.delete("assigned_to")
        metadata.delete("assigned_to_name")
        status = "new" if status.in?(rules[:release_to_new_from])
        workflow_status = "new"
      end

      metadata["workflow_status"] = workflow_status if rules[:mirrors_workflow_status]
      record.update!(metadata: metadata, status: status)

      held_before != metadata["assigned_to"]
    end

    def audit_entry
      { "type" => record.class.name, "id" => record.id }
    end

    private

    # Only the handing-out questions need these. Who holds a record is written
    # in its metadata whatever kind it is, and the Requests board asks that of a
    # checkout -- which this board never hands out and so has no rules for.
    def rules
      @rules ||= RULES.fetch(record.class.name.to_sym)
    end

    def note_history(metadata, by:, to_name:, to_id: nil)
      history = Array(metadata["assignment_history"])
      history << {
        "assigned_to_id" => to_id,
        "assigned_to_name" => to_name,
        "assigned_by_id" => by.id,
        "assigned_by_name" => by.name,
        "timestamp" => Time.current.iso8601
      }.compact
      metadata["assignment_history"] = history
    end
  end
end
