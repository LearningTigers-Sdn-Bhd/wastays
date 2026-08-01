# frozen_string_literal: true

require "ostruct"

module Bookings
  class ProcessLateCheckout
    RESOLUTIONS = %w[charge waive reject].freeze

    def self.call(booking:, user:, params: {}, options: {})
      new(booking: booking, user: user, params: params, options: options).call
    end

    def initialize(booking:, user:, params: {}, options: {})
      @booking = booking
      @user = user
      @params = params
      @options = options
      @charged = false
      @rejected = false
    end

    def call
      NightAudits::OperationalChangeGuard.call!(hotel: @booking.hotel, action: :process_late_checkout)
      result = nil

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          unless @booking.status == "due_out_detected"
            result = failure("Booking does not have a detected due-out.")
            raise ActiveRecord::Rollback
          end

          unless RESOLUTIONS.include?(@params[:resolution])
            result = failure("Choose how to resolve this late checkout.")
            raise ActiveRecord::Rollback
          end

          if reject_late_checkout?
            transition_result = Bookings::TransitionStatus.new(
              booking: @booking,
              status: "checkout_required",
              user: @user,
              options: {
                event: "reject_late_checkout",
                reason: "Late checkout rejected"
              }.merge(@options.fetch(:transition_options, {}))
            ).call

            if transition_result.success?
              @rejected = true
              result = success
            else
              result = transition_result
              raise ActiveRecord::Rollback
            end

            next
          end

          stay_result = update_checkout_period
          unless stay_result.success?
            result = failure(stay_result.errors.to_sentence)
            raise ActiveRecord::Rollback
          end

          charge_result = post_charge_if_requested
          unless charge_result.success?
            result = charge_result
            raise ActiveRecord::Rollback
          end

          transition_result = Bookings::TransitionStatus.new(
            booking: @booking,
            status: "checked_in",
            user: @user,
            options: { event: "resolve_late_checkout" }.merge(@options.fetch(:transition_options, {}))
          ).call

          if transition_result.success?
            restore_result = HousekeepingTasks::RestoreLateCheckoutRoomStatuses.new(
              booking: @booking,
              user: @user
            ).call

            if restore_result.success?
              result = success
            else
              result = failure(restore_result.error)
              raise ActiveRecord::Rollback
            end
          else
            result = transition_result
            raise ActiveRecord::Rollback
          end
        end
      end

      result || failure("Unknown error occurred during late checkout processing.")
    rescue StandardError => e
      failure(e.message)
    end

    private

    def update_checkout_period
      return OpenStruct.new(success?: true) if @params[:check_out].blank?

      Bookings::UpdateStayService.new(
        booking: @booking,
        params: { check_out: @params[:check_out] },
        user: @user
      ).call
    end

    def post_charge_if_requested
      return OpenStruct.new(success?: true) unless charge_requested?
      return failure("Charge amount must be greater than zero.") unless @params[:amount].to_d.positive?
      return failure("Booking folio is missing.") unless @booking.booking_folio.present?

      @charged = true
      Folios::Charges::PostCategoryCharge.call(
        folio: @booking.booking_folio,
        user: @user,
        category: "late_checkout_charge",
        amount: @params[:amount],
        description: "Late Checkout Charge",
        options: @options.fetch(:charge_options, {})
      )
    end

    def charge_requested?
      @params[:resolution] == "charge"
    end

    def reject_late_checkout?
      @params[:resolution] == "reject"
    end

    def success
      OpenStruct.new(success?: true, booking: @booking, charged?: @charged, rejected?: @rejected)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
