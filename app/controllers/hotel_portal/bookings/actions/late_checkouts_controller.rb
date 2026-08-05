# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based late-checkout resolution. Renders the charge form (GET) and
      # processes the resolution outcome (POST) — approve with a charge, approve
      # without a charge, or reject (which moves the booking to checkout_required).
      # Supports single and group batch targeting.
      #
      # Business rules live in Bookings::ProcessLateCheckout; this controller only
      # orchestrates authorization, input, rendering, and completion.
      class LateCheckoutsController < BaseController
        include GroupLifecycleTargeting

        helper_method :late_checkout_policy_per_booking?

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          return batch_process if selected_lifecycle_batch?(@booking)

          result = ::Bookings::ProcessLateCheckout.call(
            booking: @booking,
            user: current_user,
            params: late_checkout_params
          )

          return complete_action(alert: result.error) unless result.success?

          complete_action(notice: outcome_notice(result))
        end

        def batch_process
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :late_checkout)
          results = []

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = ::Bookings::ProcessLateCheckout.call(booking: booking, user: current_user, params: late_checkout_params)
              raise BatchTargetError, result.error unless result.success?

              results << result
            end
          end

          past_tense = results.first.rejected? ? "late checkout rejected" : "resolved for late checkout"
          complete_action(notice: batch_lifecycle_notice(bookings, past_tense))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        # On rejection the booking becomes checkout_required; navigate back to the
        # control panel where checkout can be completed (the checkout flow is not
        # part of this Sheet family yet).
        def outcome_notice(result)
          return "Late checkout rejected. Complete checkout to resolve the booking." if result.rejected?

          result.charged? ? "Late checkout charge applied." : "Late checkout resolved without charge."
        end

        # A group sheet resolves every selected booking at once, and each one gets
        # its own policy figure — there is no single number to show.
        def late_checkout_policy_per_booking?
          @booking.group_booking_id.present? || selected_lifecycle_batch?(@booking)
        end

        def late_checkout_params
          params.permit(:resolution, :amount, :check_out, :charge_source, :custom_type, :custom_value)
        end
      end
    end
  end
end
