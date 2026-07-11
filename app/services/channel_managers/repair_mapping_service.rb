# frozen_string_literal: true

module ChannelManagers
  # Repoints the hotel + room type Channex mappings back to the property that
  # its rate plans actually belong to, when DiagnoseMappingService finds drift.
  class RepairMappingService
    Result = Struct.new(:success?, :message)

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      diagnosis = ChannelManagers::DiagnoseMappingService.new(hotel: @hotel).call
      return Result.new(true, "No mapping drift detected. Channel mapping is already consistent.") unless diagnosis.mismatched?

      ActiveRecord::Base.transaction do
        @hotel.channel_mapping.update!(external_id: diagnosis.correct_property_id)

        diagnosis.correct_room_type_ids.each do |room_type_id, external_id|
          room_type = @hotel.room_types.find(room_type_id)
          mapping = room_type.channel_mapping || room_type.create_channel_mapping(provider: "channex", external_id: "pending")
          mapping.update!(external_id: external_id)
        end
      end

      refresh_result = ChannelManagers::FullRefreshService.new(hotel: @hotel).call

      Result.new(
        true,
        "Repaired #{diagnosis.mismatches.size} mismatched mapping(s); now pointing at property #{diagnosis.correct_property_id}. #{refresh_result.message}"
      )
    rescue StandardError => e
      Result.new(false, e.message)
    end
  end
end
