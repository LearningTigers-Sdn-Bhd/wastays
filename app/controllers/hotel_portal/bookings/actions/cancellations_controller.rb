# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based booking cancellation. Renders the cancellation form into the
      # requesting Sheet frame (GET) and performs the cancellation (POST),
      # supporting single and group batch targeting.
      #
      # When the hotel's cancellation policy charges a fee, the fee posts to the
      # folio inside the same transaction as the status change and before it, so
      # a cancellation that fails leaves no orphan fee behind. The refund side is
      # display only — money goes back through the existing deposit / refund
      # request path, not from here.
      #
      # Business rules live in Bookings::TransitionStatus, Cancellations::Quote
      # and Folios::Charges::PostCategoryCharge; this controller only orchestrates
      # authorization, input, rendering, and completion.
      class CancellationsController < BaseController
        include GroupLifecycleTargeting

        helper_method :cancellation_quote, :cancellation_policy_per_booking?

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          if cancellation_reason.blank?
            @booking.errors.add(:base, "Cancellation reason is required.")
            return render_cancellation_failure
          end

          return batch_cancel if selected_lifecycle_batch?(@booking)

          result = cancel(@booking)

          if result.success?
            complete_action(notice: cancellation_notice(@booking))
          else
            complete_action(alert: result.error)
          end
        end

        def batch_cancel
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :cancel)

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = cancel(booking)
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_action(notice: batch_lifecycle_notice(bookings, "cancelled"))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        # The fee posts before the transition so a failed transition rolls it back.
        def cancel(booking)
          result = nil

          ActiveRecord::Base.transaction(requires_new: true) do
            fee_result = post_cancellation_fee(booking)
            if fee_result.present? && !fee_result.success?
              result = fee_result
              raise ActiveRecord::Rollback
            end

            result = transition(booking)
            raise ActiveRecord::Rollback unless result.success?
          end

          result
        end

        def post_cancellation_fee(booking)
          return nil unless charge_cancellation_fee?

          quote = cancellation_quote(booking)
          return nil unless quote.success?
          return nil unless quote.fee_amount.to_d.positive?

          folio = cancellation_folio(booking)
          return failure_result("Booking folio is missing.") if folio.blank?

          ::Folios::Charges::PostCategoryCharge.call(
            folio: folio,
            user: current_user,
            category: "cancellation_charge",
            amount: quote.fee_amount,
            description: "Cancellation Fee"
          )
        end

        def cancellation_folio(booking)
          return booking.booking_folio if booking.booking_folio.present?

          ::Folios::Lifecycle::InitializeForBooking.call(
            booking: booking,
            user: current_user,
            options: { posting_source: "cancellation" },
            lock: false
          )
        end

        def transition(booking)
          ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "cancelled",
            user: current_user,
            options: { reason: cancellation_reason }
          ).call
        end

        def cancellation_notice(booking)
          return "Booking cancelled successfully." unless charge_cancellation_fee?

          quote = cancellation_quote(booking)
          return "Booking cancelled successfully." unless quote&.success? && quote.fee_amount.to_d.positive?

          "Booking cancelled. Cancellation fee of #{booking.hotel.default_currency} #{format('%.2f', quote.fee_amount)} posted."
        end

        # Recomputed here on submit; the sheet's figures are display only.
        def cancellation_quote(booking = @booking)
          (@cancellation_quotes ||= {})[booking.id] ||= ::Cancellations::Quote.call(booking: booking)
        end

        # A group cancellation resolves every selected booking at once, and each
        # one gets its own fee — there is no single figure to show.
        def cancellation_policy_per_booking?
          @booking.group_booking_id.present? || selected_lifecycle_batch?(@booking)
        end

        # Absent means waive: a client that never saw the fee must not post one.
        def charge_cancellation_fee?
          ActiveModel::Type::Boolean.new.cast(cancellation_params[:charge_fee]).present?
        end

        def cancellation_reason
          cancellation_params[:cancellation_reason].to_s.strip
        end

        def cancellation_params
          params.permit(:cancellation_reason, :charge_fee)
        end

        def failure_result(error)
          OpenStruct.new(success?: false, error: error)
        end

        def render_cancellation_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/cancellations/form",
                locals: { booking: @booking }
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
