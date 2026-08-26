# frozen_string_literal: true

class BackfillRoomsFromRoomTypes < ActiveRecord::Migration[8.0]
  class MigrationRoomType < ActiveRecord::Base
    self.table_name = "room_types"
  end

  class MigrationRoom < ActiveRecord::Base
    self.table_name = "rooms"
  end

  def up
    candidates = room_candidates
    raise_for_collisions!(candidates)

    candidates.each do |candidate|
      room = MigrationRoom.find_or_initialize_by(
        hotel_id: candidate.fetch(:hotel_id),
        number: candidate.fetch(:number)
      )
      room.assign_attributes(
        room_type_id: candidate.fetch(:room_type_id),
        room_group_id: candidate[:room_group_id],
        position: candidate.fetch(:position),
        archived_at: nil
      )
      room.save!
    end
  end

  def down
    # JSON remains authoritative in this milestone. The preceding schema
    # migration removes this shadow table after this data migration rolls back.
    MigrationRoom.delete_all
  end

  private

  def room_candidates
    MigrationRoomType.order(:hotel_id, :id).flat_map do |room_type|
      Array(room_type[:room_numbers]).flatten.each_with_index.filter_map do |raw_number, position|
        number = raw_number.to_s.strip
        next if number.blank?

        {
          hotel_id: room_type.hotel_id,
          room_type_id: room_type.id,
          room_type_name: room_type.name,
          room_group_id: room_type.room_group_id,
          number: number,
          position: position
        }
      end
    end
  end

  def raise_for_collisions!(candidates)
    source_collisions = candidates.group_by { |candidate| [ candidate.fetch(:hotel_id), candidate.fetch(:number) ] }
                                  .select { |_identity, entries| entries.size > 1 }
    existing_collisions = candidates.filter_map do |candidate|
      room = MigrationRoom.find_by(hotel_id: candidate.fetch(:hotel_id), number: candidate.fetch(:number))
      next if room.blank? || room.room_type_id == candidate.fetch(:room_type_id)

      [ candidate, room ]
    end

    return if source_collisions.empty? && existing_collisions.empty?

    details = source_collisions.map do |(hotel_id, number), entries|
      owners = entries.map { |entry| "#{entry.fetch(:room_type_id)} (#{entry.fetch(:room_type_name)})" }.join(", ")
      "hotel #{hotel_id}, room #{number.inspect}, room types #{owners}"
    end
    details.concat(existing_collisions.map do |candidate, room|
      "hotel #{candidate.fetch(:hotel_id)}, room #{candidate.fetch(:number).inspect}, " \
        "room types #{room.room_type_id} and #{candidate.fetch(:room_type_id)} (#{candidate.fetch(:room_type_name)})"
    end)

    raise ActiveRecord::MigrationError,
          "Cannot backfill physical rooms because room numbers collide after trimming: #{details.uniq.join('; ')}. " \
          "Rename each duplicate room number in Room Inventory, then run the migration again."
  end
end
