# frozen_string_literal: true

module HotelPortal
  module Requests
    # The one way to reach a request the board owns.
    #
    # Three tables stand behind a board card and each is scoped to a hotel
    # differently: a housekeeping request carries its own hotel_id when a
    # dispatcher raised it and nothing but a booking when a guest raised it
    # through the concierge page, while complaints and checkouts only ever
    # reach a hotel through their booking. Getting that wrong reads another
    # hotel's request, so it is settled here once instead of in each caller.
    class Finder
      MODELS = {
        "housekeeping" => HousekeepingRequest,
        "complaint" => ComplaintRequest,
        "checkout" => CheckOutRequest
      }.freeze

      # `kinds` narrows what a caller is willing to act on. Cancelling wants
      # only the two kinds that keep internal notes, and asking for a third is
      # a lookup that cannot succeed rather than a record that is missing --
      # but both leave the caller with nothing, so both raise.
      def initialize(hotel:, kind:, request_id:, kinds: MODELS.keys)
        @hotel = hotel
        @kind = kind.to_s
        @request_id = request_id
        @kinds = kinds.map(&:to_s)
      end

      def call
        record = model.includes(:booking).find(@request_id)
        raise ActiveRecord::RecordNotFound unless hotel_id_for(record) == @hotel.id

        record
      end

      private

      def model
        raise ActiveRecord::RecordNotFound unless @kinds.include?(@kind)

        MODELS.fetch(@kind) { raise ActiveRecord::RecordNotFound }
      end

      # Its own column when it has one, and otherwise the booking it hangs off.
      def hotel_id_for(record)
        own_hotel_id = record.respond_to?(:hotel_id) ? record.hotel_id : nil
        own_hotel_id || record.booking&.hotel_id
      end
    end
  end
end
