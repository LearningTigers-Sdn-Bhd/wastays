# frozen_string_literal: true

module ChannelManagers
  # Detects drift between the hotel's mapped Channex property and the
  # property that its rate plans actually belong to on Channex. This can
  # happen when a disconnect/reconnect cycle recreates the property and
  # room types but leaves stale rate plan mappings pointing at the old one.
  class DiagnoseMappingService
    Result = Struct.new(:mismatches, :correct_property_id, :correct_room_type_ids, keyword_init: true) do
      def mismatched?
        mismatches.any?
      end
    end

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      current_property_id = @hotel.channel_mapping&.external_id
      return Result.new(mismatches: [], correct_property_id: nil, correct_room_type_ids: {}) if current_property_id.blank?

      client = Channex::Client.new
      mismatches = []
      correct_property_id = nil
      correct_room_type_ids = {}

      @hotel.room_types.includes(:rate_plans, :room_type_rate_plans).each do |room_type|
        room_type.rate_plans.each do |rate_plan|
          rtrp = room_type.room_type_rate_plans.find_by(rate_plan: rate_plan)
          mapping = rtrp&.channel_mapping
          next if mapping&.external_id.blank? || mapping.external_id.to_s.start_with?("pending")

          response = client.get("/rate_plans/#{mapping.external_id}")
          rel_property_id = response.dig("data", "relationships", "property", "data", "id")
          rel_room_type_id = response.dig("data", "relationships", "room_type", "data", "id")
          next if rel_property_id.blank?

          next if rel_property_id == current_property_id

          mismatches << {
            room_type_id: room_type.id,
            room_type_name: room_type.name,
            rate_plan_id: rate_plan.id,
            rate_plan_name: rate_plan.name,
            expected_property_id: rel_property_id
          }
          correct_property_id ||= rel_property_id
          correct_room_type_ids[room_type.id] ||= rel_room_type_id
        end
      end

      Result.new(mismatches: mismatches, correct_property_id: correct_property_id, correct_room_type_ids: correct_room_type_ids)
    end
  end
end
