# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The Room card on the Policies page.
    #
    # Occupancy, smoking, and pets belong to the room type, and the booking
    # engine enforces them there. The card reads those columns so a hotel never
    # writes a second, softer answer beside the one that is enforced.
    class RoomPolicyPresenter
      Row = Data.define(:name, :max_adults, :max_children, :smoking_allowed, :pets_allowed)

      def initialize(hotel)
        @hotel = hotel
      end

      def rows
        @rows ||= hotel.room_types.order(:name).map do |room_type|
          Row.new(
            name: room_type.name.presence || "Untitled room type",
            max_adults: room_type.max_adults,
            max_children: room_type.max_children,
            smoking_allowed: room_type.smoking_allowed,
            pets_allowed: room_type.pets_allowed
          )
        end
      end

      def any? = rows.any?

      def smoking_anywhere? = rows.any?(&:smoking_allowed)

      def pets_anywhere? = rows.any?(&:pets_allowed)

      private

      attr_reader :hotel
    end
  end
end
