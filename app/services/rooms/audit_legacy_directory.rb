# frozen_string_literal: true

module Rooms
  class AuditLegacyDirectory
    Finding = Data.define(
      :code,
      :hotel_id,
      :hotel_name,
      :room_type_id,
      :room_type_name,
      :room_number,
      :message
    )
    Result = Data.define(:blocking_issues) do
      def success? = blocking_issues.empty?
    end

    def initialize(room_types: RoomType.all)
      @room_types = room_types
    end

    def call
      findings = []
      number_owners = Hash.new { |hash, key| hash[key] = [] }

      @room_types.includes(:hotel).find_each do |room_type|
        raw_numbers = Array(room_type[:room_numbers]).flatten
        add_format_findings(findings, room_type, raw_numbers)
        add_quantity_finding(findings, room_type, raw_numbers)
        collect_number_owners(number_owners, room_type, raw_numbers)
      end

      add_cross_type_findings(findings, number_owners)

      Result.new(blocking_issues: findings.freeze)
    end

    private

    def add_format_findings(findings, room_type, raw_numbers)
      raw_numbers.each do |raw_number|
        if raw_number.blank?
          findings << finding(room_type, :blank_room_number, raw_number, "Room numbers contain a blank value.")
        elsif raw_number.to_s != raw_number.to_s.strip
          findings << finding(
            room_type,
            :untrimmed_room_number,
            raw_number,
            "Room number #{raw_number.inspect} contains leading or trailing spaces."
          )
        end
      end

      normalized_counts(raw_numbers).each do |number, count|
        next unless count > 1

        findings << finding(
          room_type,
          :duplicate_room_number,
          number,
          "Room number #{number.inspect} occurs #{count} times after normalization."
        )
      end
    end

    def add_quantity_finding(findings, room_type, raw_numbers)
      configured_count = raw_numbers.count(&:present?)
      return if configured_count.zero?
      return if configured_count == room_type.quantity.to_i

      findings << finding(
        room_type,
        :quantity_mismatch,
        nil,
        "The quantity is #{room_type.quantity}, but the room-number list contains #{configured_count} values."
      )
    end

    def collect_number_owners(number_owners, room_type, raw_numbers)
      normalized_counts(raw_numbers).each_key do |number|
        number_owners[[ room_type.hotel_id, number ]] << room_type
      end
    end

    def add_cross_type_findings(findings, number_owners)
      number_owners.each do |(_hotel_id, number), room_types|
        owners = room_types.uniq(&:id)
        next unless owners.many?

        owner_names = owners.map(&:name).sort.join(", ")
        owners.each do |room_type|
          findings << finding(
            room_type,
            :cross_room_type_duplicate,
            number,
            "Room number #{number.inspect} belongs to multiple room types: #{owner_names}."
          )
        end
      end
    end

    def normalized_counts(raw_numbers)
      raw_numbers.each_with_object(Hash.new(0)) do |raw_number, counts|
        number = raw_number.to_s.strip
        counts[number] += 1 if number.present?
      end
    end

    def finding(room_type, code, room_number, message)
      Finding.new(
        code:,
        hotel_id: room_type.hotel_id,
        hotel_name: room_type.hotel.name,
        room_type_id: room_type.id,
        room_type_name: room_type.name,
        room_number: room_number&.to_s,
        message:
      )
    end
  end
end
