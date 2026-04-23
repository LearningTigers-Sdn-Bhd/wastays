# frozen_string_literal: true

module Admin
  module Hotels
    class ApproveService
      Result = Struct.new(:success?, :reactivating?, :error)

      def initialize(hotel:)
        @hotel = hotel
      end

      def call
        reactivating = @hotel.status == "suspended" || @hotel.account.status == "suspended"

        ActiveRecord::Base.transaction do
          @hotel.account.update!(status: "active")
          @hotel.update!(status: "approved")
        end

        Result.new(true, reactivating, nil)
      rescue => e
        Result.new(false, false, e.message)
      end
    end
  end
end
