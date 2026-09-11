# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # One row of the Amenities table: an amenity, its saved guest details, and
    # how complete those details are.
    #
    # Status counts the fields a guest asks about, not the row in the database.
    # A saved row with three empty fields is not ready, and the old page called
    # it ready because the record existed.
    class AmenityRow
      CONTENT_FIELDS = %i[location opening_hours fee_information].freeze

      # Loads the details of every given amenity in one query and pairs them up.
      def self.build(hotel:, amenities:)
        amenities = amenities.to_a
        details = hotel.hotel_amenity_details.where(amenity: amenities).index_by(&:amenity_id)
        amenities.map { |amenity| new(amenity: amenity, detail: details[amenity.id]) }
      end

      def initialize(amenity:, detail: nil)
        @amenity = amenity
        @detail = detail
      end

      attr_reader :amenity, :detail

      delegate :id, :name, :slug, :category, to: :amenity

      def location = detail&.location.presence
      def opening_hours = detail&.opening_hours.presence
      def fee_information = detail&.fee_information.presence
      def reservation_required? = detail&.reservation_required? || false

      def filled_count
        CONTENT_FIELDS.count { |field| public_send(field).present? }
      end

      def ready? = filled_count == CONTENT_FIELDS.size
      def started? = filled_count.positive?

      def status_label
        return "Ready" if ready?
        return "Not started" unless started?

        "Incomplete"
      end

      def status_variant
        return :success if ready?
        return :neutral unless started?

        :warning
      end

      # The line under the amenity name in the selection sheet, so an operator
      # sees which amenities still need details before the sheet closes.
      def selection_description
        [ category, status_label ].compact_blank.join(" · ")
      end

      def search_value
        "#{name} #{category}".downcase
      end
    end
  end
end
