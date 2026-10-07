# frozen_string_literal: true

module HotelPortal
  module OtaLogins
    class Create
      Result = Data.define(:credential) do
        def success? = credential.persisted?
      end

      def self.call(...) = new(...).call

      def initialize(hotel:, attributes:)
        @credential = hotel.hotel_ota_credentials.build(attributes)
      end

      def call
        credential.save
        Result.new(credential: credential)
      rescue ActiveRecord::RecordNotUnique
        credential.errors.add(:channel_name, "already has credentials for this property")
        Result.new(credential: credential)
      end

      private

      attr_reader :credential
    end
  end
end
