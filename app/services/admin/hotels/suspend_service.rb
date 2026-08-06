# frozen_string_literal: true

module Admin
  module Hotels
    class SuspendService
      Result = Struct.new(:success?, :error)

      def initialize(hotel:)
        @hotel = hotel
      end

      def call
        ActiveRecord::Base.transaction do
          @hotel.account.update!(
            pre_suspension_status: @hotel.account.status,
            status: "suspended"
          )
          @hotel.update!(
            pre_suspension_status: @hotel.status,
            status: "suspended"
          )
        end
        Result.new(true, nil)
      rescue => e
        Result.new(false, e.message)
      end
    end
  end
end
