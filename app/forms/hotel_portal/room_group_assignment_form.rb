# frozen_string_literal: true

module HotelPortal
  class RoomGroupAssignmentForm
    include ActiveModel::Model

    attr_accessor :room_group_id, :new_group_name, :room_type_ids

    validates :room_group_id, presence: true
    validate :room_types_selected
    validate :new_group_named

    private

    def room_types_selected
      errors.add(:room_type_ids, "Select at least one room category.") if Array(room_type_ids).compact_blank.empty?
    end

    def new_group_named
      return unless room_group_id.to_s == "new" && new_group_name.blank?

      errors.add(:new_group_name, "Enter a name for the new room group.")
    end
  end
end
