# frozen_string_literal: true

module BoatSchedules
  # Saves every changed slot on the Boat Settings page in one submit, so
  # editing several slots (a common bulk-edit case) isn't one round trip per
  # row. All-or-nothing: if one slot fails validation, none of the slots in
  # the batch are saved, so the page reload reflects an unambiguous state.
  class BulkUpdate
    Result = ApplicationResult.define(:updated_count)

    def self.call(...) = new(...).call

    def initialize(hotel:, attributes:)
      @hotel = hotel
      @attributes = attributes
    end

    def call
      return Result.success(updated_count: 0) if @attributes.blank?

      slots = @hotel.hotel_boat_schedules.where(id: @attributes.keys).index_by { |slot| slot.id.to_s }
      missing = @attributes.keys - slots.keys
      return Result.failure("One or more slots could not be found.") if missing.any?

      error = nil
      ActiveRecord::Base.transaction do
        @attributes.each do |id, slot_attributes|
          slot = slots.fetch(id)
          next if slot.update(slot_attributes)

          error = slot.errors.full_messages.to_sentence
          raise ActiveRecord::Rollback
        end
      end
      return Result.failure(error) if error

      Result.success(updated_count: @attributes.size)
    end
  end
end
