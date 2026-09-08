# frozen_string_literal: true

module HotelPortal
  module Amenities
    # Writes the guest details of one amenity. The row is created on the first
    # save, so the table can offer an Edit action for an amenity that has no
    # details yet.
    class SaveDetail
      PERMITTED = %i[
        location opening_hours fee_information
        reservation_required reservation_instructions guest_notes
      ].freeze

      Result = Data.define(:detail) do
        def success? = detail.errors.empty?
      end

      def self.call(...) = new(...).call

      def initialize(hotel:, amenity:, attributes:)
        @hotel = hotel
        @amenity = amenity
        @attributes = attributes.to_h.symbolize_keys.slice(*PERMITTED)
      end

      def call
        detail = hotel.hotel_amenity_details.find_or_initialize_by(amenity: amenity)
        detail.assign_attributes(attributes)
        detail.save
        Result.new(detail: detail)
      end

      private

      attr_reader :hotel, :amenity, :attributes
    end
  end
end
