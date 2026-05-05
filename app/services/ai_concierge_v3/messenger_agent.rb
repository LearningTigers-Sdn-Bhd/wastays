module AiConciergeV3
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
      builder_message(reply_type) || context[:message].presence || MessageBuilders::FallbackBuilder::DEFAULT_MESSAGE
    end

    def builder_message(reply_type)
      booking_builder.call(reply_type) || hotel_info_builder.call(reply_type) || room_info_builder.call(reply_type)
    end

    def booking_builder
      @booking_builder ||= MessageBuilders::BookingActionsBuilder.new(hotel:, context:)
    end

    def hotel_info_builder
      @hotel_info_builder ||= MessageBuilders::HotelInfoBuilder.new(hotel:, context:)
    end

    def room_info_builder
      @room_info_builder ||= MessageBuilders::RoomInfoBuilder.new(hotel:, context:)
    end
  end
end
