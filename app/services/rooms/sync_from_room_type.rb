# frozen_string_literal: true

module Rooms
  class SyncFromRoomType
    class Error < StandardError; end

    Result = ApplicationResult.define(:rooms)

    def self.call(room_type:)
      new(room_type:).call
    end

    def self.call!(room_type:)
      result = call(room_type:)
      raise Error, result.error unless result.success?

      result.rooms
    end

    def initialize(room_type:)
      @room_type = room_type
    end

    def call
      return failure("Save the room category before you synchronize its rooms.") unless @room_type.persisted?

      sync_rooms
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      failure(record_error(error))
    end

    private

    def desired_numbers
      @desired_numbers ||= Array(@room_type.room_numbers).flatten.compact
        .map { |number| number.to_s.strip }
        .reject(&:blank?)
    end

    def sync_rooms
      result = nil

      Room.transaction do
        @room_type.lock!
        remove_instance_variable(:@desired_numbers) if defined?(@desired_numbers)
        if desired_numbers.uniq.length != desired_numbers.length
          result = failure("Room numbers must be unique.")
          raise ActiveRecord::Rollback
        end

        hotel_rooms = Room.where(hotel_id: @room_type.hotel_id).lock.index_by(&:number)
        current_rooms = hotel_rooms.values.select do |room|
          room.room_type_id == @room_type.id && room.archived_at.nil?
        end

        conflict = desired_numbers.filter_map do |number|
          room = hotel_rooms[number]
          room if room && room.room_type_id != @room_type.id
        end.first
        if conflict
          result = failure("Room #{conflict.number} already belongs to another room category.")
          raise ActiveRecord::Rollback
        end

        removals = current_rooms.reject { |room| desired_numbers.include?(room.number) }
        guard_failure = removals.filter_map do |room|
          guard = RemovalGuard.call(room: room)
          guard unless guard.success?
        end.first
        if guard_failure
          result = failure(guard_failure.error)
          raise ActiveRecord::Rollback
        end

        archived_at = Time.current
        removals.each { |room| room.update!(archived_at: archived_at) }

        rooms = desired_numbers.each_with_index.map do |number, position|
          room = hotel_rooms[number]
          if room
            room.update!(archived_at: nil, position: position)
          else
            room = Room.create!(
              hotel: @room_type.hotel,
              room_type: @room_type,
              number: number,
              position: position
            )
            hotel_rooms[number] = room
          end
          room
        end

        result = Result.success(rooms: rooms)
      end

      result || failure("Rooms could not be synchronized.")
    end

    def record_error(error)
      return error.record.errors.full_messages.to_sentence if error.respond_to?(:record)

      "A room number already belongs to this property."
    end

    def failure(message)
      @room_type.errors.add(:room_numbers, message) unless @room_type.errors[:room_numbers].include?(message)
      Result.failure(message, rooms: current_active_rooms)
    end

    def current_active_rooms
      return [] unless @room_type.persisted? && Room.table_exists?

      Room.where(room_type_id: @room_type.id, archived_at: nil).order(:position, :id).to_a
    end
  end
end
