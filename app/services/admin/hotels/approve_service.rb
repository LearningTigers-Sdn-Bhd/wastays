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
        return Result.new(false, false, "Only suspended properties can use this reactivation action.") unless reactivating

        ActiveRecord::Base.transaction do
          target_account_status = if reactivating && @hotel.account.pre_suspension_status.present?
            @hotel.account.pre_suspension_status
          else
            "active"
          end

          target_hotel_status = if @hotel.pre_suspension_status.present?
            @hotel.pre_suspension_status
          else
            "live"
          end

          Rails.logger.info "[ApproveService] Reactivating: #{reactivating}, Pre-Hotel-Status: #{@hotel.pre_suspension_status}, Target: #{target_hotel_status}"

          @hotel.account.update!(status: target_account_status, pre_suspension_status: nil)
          @hotel.update!(status: target_hotel_status, pre_suspension_status: nil)
        end

        Result.new(true, reactivating, nil)
      rescue => e
        Result.new(false, false, e.message)
      end
    end
  end
end
