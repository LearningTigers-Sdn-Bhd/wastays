# frozen_string_literal: true

class BackfillRoomsFromRoomTypes < ActiveRecord::Migration[8.0]
  class MigrationRoomType < ActiveRecord::Base
    self.table_name = "room_types"
  end

  class MigrationRoom < ActiveRecord::Base
    self.table_name = "rooms"
  end

  def up
    room_types = MigrationRoomType.order(:hotel_id, :id).to_a
    candidates = room_candidates(room_types)
    raise_for_invalid_directory!(room_types, candidates)

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

  def room_candidates(room_types)
    room_types.flat_map do |room_type|
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

  def raise_for_invalid_directory!(room_types, candidates)
    issues = room_types.flat_map { |room_type| source_issues(room_type) }
    issues.concat(cross_room_type_issues(candidates))
    issues.concat(existing_room_issues(candidates))
    return if issues.empty?

    raise ActiveRecord::MigrationError,
          "Cannot backfill physical rooms because the legacy room directory is invalid: #{issues.uniq.join('; ')}. " \
          "Correct every finding in Room Inventory, then run the audit and migration again."
  end

  def source_issues(room_type)
    raw_numbers = Array(room_type[:room_numbers]).flatten
    normalized_numbers = raw_numbers.filter_map do |raw_number|
      number = raw_number.to_s.strip
      number if number.present?
    end
    issues = []

    raw_numbers.each_with_index do |raw_number, position|
      number = raw_number.to_s
      if number.strip.blank?
        issues << room_type_issue(room_type, "blank room number at position #{position}")
      elsif number != number.strip
        issues << room_type_issue(room_type, "untrimmed room number #{number.inspect}")
      end
    end

    normalized_numbers.tally.each do |number, count|
      issues << room_type_issue(room_type, "room number #{number.inspect} occurs #{count} times") if count > 1
    end

    if normalized_numbers.any? && normalized_numbers.size != room_type.quantity.to_i
      issues << room_type_issue(
        room_type,
        "quantity is #{room_type.quantity}, but the room-number list contains #{normalized_numbers.size} values"
      )
    end

    issues
  end

  def cross_room_type_issues(candidates)
    candidates.group_by { |candidate| [ candidate.fetch(:hotel_id), candidate.fetch(:number) ] }.filter_map do |(hotel_id, number), entries|
      owners = entries.uniq { |entry| entry.fetch(:room_type_id) }
      next unless owners.many?

      labels = owners.map { |entry| "#{entry.fetch(:room_type_id)} (#{entry.fetch(:room_type_name)})" }.join(", ")
      "hotel #{hotel_id}, room #{number.inspect} belongs to room types #{labels}"
    end
  end

  def existing_room_issues(candidates)
    candidates.filter_map do |candidate|
      room = MigrationRoom.find_by(hotel_id: candidate.fetch(:hotel_id), number: candidate.fetch(:number))
      next if room.blank? || room.room_type_id == candidate.fetch(:room_type_id)

      "hotel #{candidate.fetch(:hotel_id)}, room #{candidate.fetch(:number).inspect} belongs to existing room type " \
        "#{room.room_type_id} and legacy room type #{candidate.fetch(:room_type_id)} (#{candidate.fetch(:room_type_name)})"
    end
  end

  def room_type_issue(room_type, message)
    "hotel #{room_type.hotel_id}, room type #{room_type.id} (#{room_type.name}): #{message}"
  end
end
