module AiConcierge
  module Agents
    class MessengerAgent
    def initialize(hotel:, context:)
      @hotel = hotel
      @context = context
    end

    def call
      { "reply_message" => render_message }
    end

    private

    attr_reader :hotel, :context

    def render_message
      reply_type = context[:reply_type]&.to_sym
      builder_message(reply_type) || context[:message].presence || MessageBuilders::DEFAULT_MESSAGE
    end

    # Every builder dispatches on `reply_type.to_sym`, so a nil one used to
    # raise here rather than fall through -- which meant the fallback replies,
    # the ones that exist precisely for when nothing else fits, reached the
    # guest as the generic "temporarily unavailable" from TurnOrchestrator's
    # rescue. No reply type simply means no builder can render it.
    def builder_message(reply_type)
      return if reply_type.nil?

      greeting_builder.call(reply_type) || booking_builder.call(reply_type) ||
        existing_booking_builder.call(reply_type) || hotel_info_builder.call(reply_type) ||
        room_info_builder.call(reply_type)
    end

    def greeting_builder
      @greeting_builder ||= MessageBuilders::GreetingBuilder.new(hotel:, context:)
    end

    def booking_builder
      @booking_builder ||= MessageBuilders::BookingActionsBuilder.new(hotel:, context:)
    end

    def existing_booking_builder
      @existing_booking_builder ||= MessageBuilders::ExistingBookingBuilder.new(hotel:, context:)
    end

    def hotel_info_builder
      @hotel_info_builder ||= MessageBuilders::HotelInfoBuilder.new(hotel:, context:)
    end

    def room_info_builder
      @room_info_builder ||= MessageBuilders::RoomInfoBuilder.new(hotel:, context:)
    end
    end
  end
end
