# frozen_string_literal: true

module HotelPortal
  module Amenities
    # Sets which amenities a property offers. The guest details of an amenity
    # that leaves the list stay saved, so a property that adds it back does not
    # write those details again.
    class UpdateSelection
      Result = Data.define(:hotel) do
        def success? = hotel.errors.empty?
      end

      def self.call(...) = new(...).call

      def initialize(hotel:, slugs:)
        @hotel = hotel
        @slugs = Array(slugs).compact_blank.map(&:to_s).uniq
      end

      def call
        hotel.amenities = slugs
        hotel.save
        sync_channel_structure if hotel.saved_change_to_amenities?
        Result.new(hotel: hotel)
      end

      private

      attr_reader :hotel, :slugs

      # Amenities travel to the channel manager as part of the property
      # structure. ProfileForm ran this sync while it owned the field, so the
      # sheet runs it too.
      def sync_channel_structure
        return if hotel.preferred_channel_manager.blank? || hotel.channel_mapping.blank?

        ChannelManagers::SyncStructureJob.perform_later("Hotel", hotel.id, "sync")
      end
    end
  end
end
