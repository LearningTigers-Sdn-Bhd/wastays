# frozen_string_literal: true

module HotelPortal
  module RoomGroups
    class Save
      Result = Data.define(:room_group) do
        def success? = room_group.errors.empty?
      end

      def self.call(...) = new(...).call

      def initialize(hotel:, attributes:, room_group: nil)
        @hotel = hotel
        @room_group = room_group || hotel.room_groups.build
        @name = attributes[:name]
        @submitted_room_ids = Array(attributes[:room_ids]).compact_blank.map(&:to_s).uniq
      end

      def call
        room_group.name = name
        group_valid = room_group.valid?
        room_ids_valid = valid_room_ids?
        return Result.new(room_group: room_group) unless room_ids_valid && group_valid

        RoomGroup.transaction do
          if room_group.persisted?
            room_group.reload
            room_group.lock!
          end
          room_group.name = name

          current_room_ids = if room_group.persisted?
            hotel.rooms.active.where(room_group_id: room_group.id).pluck(:id)
          else
            []
          end
          affected_room_ids = (parsed_room_ids + current_room_ids).uniq.sort
          affected_rooms = hotel.rooms.active.where(id: affected_room_ids).order(:id).lock.to_a
          selected_rooms = affected_rooms.select { |room| parsed_room_ids.include?(room.id) }
          unless selected_rooms.size == parsed_room_ids.size
            room_group.errors.add(:rooms, "include one or more rooms that are not available for this property.")
            raise ActiveRecord::Rollback
          end
          if selected_rooms.any? { |room| room.room_group_id.present? && room.room_group_id != room_group.id }
            room_group.errors.add(:rooms, "include one or more rooms assigned to another room group.")
            raise ActiveRecord::Rollback
          end

          current_rooms = affected_rooms.select { |room| room.room_group_id == room_group.id }

          room_group.save!
          unassigned_ids = current_rooms.map(&:id) - parsed_room_ids
          Room.where(id: unassigned_ids).update_all(room_group_id: nil, updated_at: Time.current) if unassigned_ids.any?
          Room.where(id: parsed_room_ids).update_all(room_group_id: room_group.id, updated_at: Time.current) if parsed_room_ids.any?
        end

        Result.new(room_group: room_group)
      rescue ActiveRecord::RecordInvalid => error
        copy_record_errors(error.record)
        Result.new(room_group: room_group)
      rescue ActiveRecord::RecordNotUnique
        room_group.errors.add(:name, "has already been taken")
        Result.new(room_group: room_group)
      end

      private

      attr_reader :hotel, :room_group, :name, :submitted_room_ids

      def parsed_room_ids
        @parsed_room_ids ||= submitted_room_ids.filter_map { |id| Integer(id, exception: false) }.uniq
      end

      def valid_room_ids?
        return true if parsed_room_ids.size == submitted_room_ids.size

        room_group.errors.add(:rooms, "include one or more invalid room selections.")
        false
      end

      def copy_record_errors(record)
        record.errors.each do |error|
          room_group.errors.add(error.attribute, error.message) unless room_group.errors.added?(error.attribute, error.message)
        end
      end
    end
  end
end
