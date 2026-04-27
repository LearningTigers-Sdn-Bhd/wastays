# frozen_string_literal: true

module ChannelManagers
  class DisconnectService
    Result = Struct.new(:success?, :error)

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      ActiveRecord::Base.transaction do
        @hotel.update!(preferred_channel_manager: nil)
        @hotel.channel_mapping&.destroy
        @hotel.room_types.each { |rt| rt.channel_mapping&.destroy }
      end
      Result.new(true, nil)
    rescue => e
      Result.new(false, e.message)
    end
  end
end
