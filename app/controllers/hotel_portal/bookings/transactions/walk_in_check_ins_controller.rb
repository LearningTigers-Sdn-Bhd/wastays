# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class WalkInCheckInsController < BaseController
        def show
          return create if request.post?

          build_booking(source: "walk_in")
          render_new_booking(transaction: :walk_in_check_in)
        end

        private

        def create
          result = nil
          transition = nil

          ActiveRecord::Base.transaction do
            result = create_manual_booking(source: "walk_in")
            raise ActiveRecord::Rollback unless result.success?

            transition = ::Bookings::TransitionStatus.new(
              booking: result.booking,
              status: "checked_in",
              timestamp: result.booking.check_in,
              user: current_user
            ).call
            raise ActiveRecord::Rollback unless transition.success?
          end

          return complete_new_booking(result.booking, notice: "Walk-in guest checked in successfully.") if result&.success? && transition&.success?

          @booking = current_hotel.bookings.build(model_booking_params.merge(source: "walk_in"))
          Array(result&.errors || transition&.error).compact.each { |error| @booking.errors.add(:base, error) }
          render_new_booking(transaction: :walk_in_check_in, status: :unprocessable_content)
        end
      end
    end
  end
end
