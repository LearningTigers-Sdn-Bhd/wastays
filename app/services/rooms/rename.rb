# frozen_string_literal: true

module Rooms
  # Changes the number of a physical room and carries its operational records
  # with it.
  #
  # The room keeps its id, so nothing loses its link. What moves is the label:
  # the room statuses, blocks, and locks that describe the room as it is today
  # must show the new number.
  #
  # Bookings and audit logs keep the number they were written with. A folio, a
  # registration card, or an audit trail states what happened at the time, and
  # a later rename does not change that.
  class Rename
    # Records that describe the room as it is now.
    OPERATIONAL_MODELS = [ RoomStatus, RoomBlock, RoomLock ].freeze

    # Records that state what happened, and keep their original number.
    HISTORICAL_MODELS = [ BookingRoom, RoomOperationalAuditLog ].freeze

    Result = ApplicationResult.define(:room, :renamed_counts)

    def self.call(...) = new(...).call

    def initialize(room:, number:)
      @room = room
      @number = number.to_s.strip
    end

    def call
      return failure("Enter a room number.") if @number.blank?
      return failure("Restore the room before you rename it.") if @room.archived?
      return Result.success(room: @room, renamed_counts: {}) if @number == @room.number
      return failure("Room #{@number} already belongs to this property.") if number_taken?

      rename
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      failure(record_error(error))
    end

    private

    def number_taken?
      Room.where(hotel_id: @room.hotel_id, number: @number).where.not(id: @room.id).exists?
    end

    def rename
      counts = {}

      Room.transaction do
        @room.lock!
        @room.update!(number: @number)

        OPERATIONAL_MODELS.each do |model|
          counts[model.table_name] = model.where(room_id: @room.id).update_all(
            room_number: @number, updated_at: Time.current
          )
        end
      end

      Result.success(room: @room, renamed_counts: counts.freeze)
    end

    def record_error(error)
      return error.record.errors.full_messages.to_sentence if error.respond_to?(:record)

      "Room #{@number} already belongs to this property."
    end

    def failure(message)
      Result.failure(message, room: @room, renamed_counts: {})
    end
  end
end
