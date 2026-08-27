# frozen_string_literal: true

module Rooms
  class ReconcileDirectory
    Issue = Data.define(:type, :room_type_id, :room_id, :number, :expected, :actual, :message)
    Result = Data.define(:summary, :issues) do
      def reconciled? = issues.empty?
      alias_method :success?, :reconciled?
    end

    def self.call(...) = new(...).call

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      room_types = hotel.room_types.includes(:room_group).order(:id).to_a
      expected_entries, issues = expected_directory(room_types)
      rooms = relevant_rooms(room_types)

      issues.concat(directory_issues(expected_entries, rooms))
      issues.freeze

      Result.new(
        summary: {
          room_types: room_types.size,
          expected_rooms: expected_entries.size,
          active_rooms: rooms.count { |room| room.hotel_id == hotel.id && room.archived_at.nil? },
          archived_rooms: rooms.count { |room| room.hotel_id == hotel.id && room.archived_at.present? },
          issues: issues.size,
          issue_counts: issues.each_with_object(Hash.new(0)) { |issue, counts| counts[issue.type] += 1 }.freeze
        }.freeze,
        issues:
      )
    end

    private

    attr_reader :hotel

    def expected_directory(room_types)
      issues = []
      entries = room_types.flat_map do |room_type|
        raw_numbers = Array(room_type[:room_numbers]).flatten
        add_source_issues(issues, room_type, raw_numbers)

        raw_numbers.each_with_index.filter_map do |raw_number, position|
          number = raw_number.to_s.strip
          next if number.blank?

          {
            hotel_id: room_type.hotel_id,
            room_type_id: room_type.id,
            number:,
            position:
          }
        end
      end

      add_hotel_duplicate_issues(issues, entries)
      [ entries, issues ]
    end

    def add_source_issues(issues, room_type, raw_numbers)
      raw_numbers.each_with_index do |raw_number, position|
        if raw_number.to_s.strip.blank?
          issues << issue(
            :blank_number,
            room_type_id: room_type.id,
            number: raw_number.to_s,
            actual: { position: },
            message: "Room type #{room_type.id} contains a blank room number at position #{position}."
          )
        elsif raw_number.to_s != raw_number.to_s.strip
          issues << issue(
            :untrimmed_number,
            room_type_id: room_type.id,
            number: raw_number.to_s,
            expected: { number: raw_number.to_s.strip },
            actual: { number: raw_number.to_s },
            message: "Room number #{raw_number.inspect} in room type #{room_type.id} contains outer spaces."
          )
        end
      end

      normalized_numbers = raw_numbers.filter_map do |raw_number|
        number = raw_number.to_s.strip
        number if number.present?
      end
      normalized_numbers.tally.each do |number, count|
        next unless count > 1

        issues << issue(
          :duplicate_json_number,
          room_type_id: room_type.id,
          number:,
          actual: { count: },
          message: "Room number #{number.inspect} occurs #{count} times in room type #{room_type.id}."
        )
      end

      return if normalized_numbers.empty? || normalized_numbers.size == room_type.quantity.to_i

      issues << issue(
        :quantity_mismatch,
        room_type_id: room_type.id,
        expected: { quantity: room_type.quantity.to_i },
        actual: { room_numbers: normalized_numbers.size },
        message: "Room type #{room_type.id} has quantity #{room_type.quantity}, but it has #{normalized_numbers.size} room numbers."
      )
    end

    def add_hotel_duplicate_issues(issues, entries)
      entries.group_by { |entry| [ entry.fetch(:hotel_id), entry.fetch(:number) ] }.each do |(_hotel_id, number), matches|
        owner_ids = matches.map { |entry| entry.fetch(:room_type_id) }.uniq
        next unless matches.size > 1 && owner_ids.size > 1

        issues << issue(
          :duplicate_hotel_number,
          number:,
          actual: { room_type_ids: owner_ids.sort },
          message: "Room number #{number.inspect} belongs to multiple room types in hotel #{hotel.id}: #{owner_ids.sort.join(', ')}."
        )
      end
    end

    def relevant_rooms(room_types)
      room_type_ids = room_types.map(&:id)
      relation = Room.where(hotel_id: hotel.id)
      relation = relation.or(Room.where(room_type_id: room_type_ids)) if room_type_ids.any?
      relation.includes(:room_type, :room_group).order(:id).to_a
    end

    def directory_issues(expected_entries, rooms)
      issues = []
      expected_by_number = expected_entries.group_by { |entry| entry.fetch(:number) }
      hotel_rooms_by_number = rooms.select { |room| room.hotel_id == hotel.id }.group_by(&:number)

      rooms.each do |room|
        next if room.room_type.hotel_id == room.hotel_id

        issues << issue(
          :wrong_hotel,
          room_type_id: room.room_type_id,
          room_id: room.id,
          number: room.number,
          expected: { hotel_id: room.room_type.hotel_id },
          actual: { hotel_id: room.hotel_id },
          message: "Room #{room.id} belongs to hotel #{room.hotel_id}, but its room type belongs to hotel #{room.room_type.hotel_id}."
        )
      end

      expected_entries.uniq { |entry| [ entry.fetch(:hotel_id), entry.fetch(:number) ] }.each do |expected|
        room = hotel_rooms_by_number.fetch(expected.fetch(:number), []).first
        if room.blank?
          issues << missing_room_issue(expected)
          next
        end

        if room.archived_at.present?
          issues << issue(
            :expected_room_archived,
            room_type_id: expected.fetch(:room_type_id),
            room_id: room.id,
            number: room.number,
            message: "Room #{room.number.inspect} is present in Room Inventory, but physical room #{room.id} is archived."
          )
          next
        end

        issues.concat(attribute_issues(expected, room))
      end

      rooms.each do |room|
        next unless room.hotel_id == hotel.id && room.archived_at.nil?
        next if expected_by_number.key?(room.number)

        issues << issue(
          :unexpected_active_room,
          room_type_id: room.room_type_id,
          room_id: room.id,
          number: room.number,
          message: "Physical room #{room.id} is active, but Room Inventory does not contain room number #{room.number.inspect}."
        )
      end

      issues
    end

    def missing_room_issue(expected)
      issue(
        :missing_room,
        room_type_id: expected.fetch(:room_type_id),
        number: expected.fetch(:number),
        expected: expected,
        message: "Room Inventory contains room #{expected.fetch(:number).inspect}, but the physical-room directory does not contain it."
      )
    end

    def attribute_issues(expected, room)
      issues = []
      compare_attribute(issues, :wrong_room_type, :room_type_id, expected, room)
      compare_attribute(issues, :wrong_position, :position, expected, room)
      issues
    end

    def compare_attribute(issues, type, attribute, expected, room)
      expected_value = expected.fetch(attribute)
      actual_value = room.public_send(attribute)
      return if expected_value == actual_value

      issues << issue(
        type,
        room_type_id: expected.fetch(:room_type_id),
        room_id: room.id,
        number: room.number,
        expected: { attribute => expected_value },
        actual: { attribute => actual_value },
        message: "Room #{room.id} has #{attribute} #{actual_value.inspect}, but Room Inventory requires #{expected_value.inspect}."
      )
    end

    def issue(type, room_type_id: nil, room_id: nil, number: nil, expected: nil, actual: nil, message:)
      Issue.new(type:, room_type_id:, room_id:, number:, expected:, actual:, message:)
    end
  end
end
