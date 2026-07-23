# frozen_string_literal: true

require "ostruct"

module Bookings
  class ProcessEarlyDeparture
    def self.call(booking:, user:, params: {}, options: {})
      new(booking: booking, user: user, params: params, options: options).call
    end

    def initialize(booking:, user:, params: {}, options: {})
      @booking = booking
      @user = user
      @params = params
      @options = options
    end

    def call
      result = nil
      Booking.transaction do
        @booking.with_lock do
          @booking.reload
          unless @booking.checked_in?
            result = failure("Booking is not checked in.")
            raise ActiveRecord::Rollback
          end

          departure_date = early_departure_date
          old_check_out = @booking.check_out.to_date
          eligibility_error = validate_departure_date(departure_date)
          if eligibility_error.present?
            result = failure(eligibility_error)
            raise ActiveRecord::Rollback
          end

          if assess_charge?
            charge_result = post_charge
            unless charge_result.success?
              result = charge_result
              raise ActiveRecord::Rollback
            end
          end

          truncate_stay!(departure_date, old_check_out)

          early_checkout_charges_result = post_early_checkout_charges(departure_date, old_check_out)
          unless early_checkout_charges_result.success?
            result = early_checkout_charges_result
            raise ActiveRecord::Rollback
          end

          if defer_checkout?
            result = success
            next
          end

          checkout_result = Bookings::TransitionStatus.new(
            booking: @booking,
            status: "completed",
            user: @user,
            timestamp: @options[:timestamp],
            options: @options
          ).call

          if checkout_result.success?
            result = success
          else
            result = checkout_result
            raise ActiveRecord::Rollback
          end
        end
      end
      result || failure("Unknown error occurred during early departure processing.")
    rescue StandardError => e
      failure(e.message)
    end

    private

    def assess_charge?
      @params[:apply_charge] == "1" || @params[:apply_charge] == "true"
    end

    def defer_checkout?
      ActiveModel::Type::Boolean.new.cast(@options[:defer_checkout])
    end

    def early_departure_date
      timestamp = @options[:timestamp].presence || Time.current
      @booking.hotel.business_date_for(timestamp).to_date
    end

    def validate_departure_date(departure_date)
      return "Early departure date cannot be before check-in date." if departure_date < @booking.check_in.to_date
      return "Booking is not eligible for early departure." if departure_date >= @booking.check_out.to_date

      nil
    end

    def truncate_stay!(departure_date, old_check_out)
      Bookings::InventoryManager.new(@booking).release_by_dates(departure_date, old_check_out)
      @booking.update!(check_out: Bookings::ScheduledStay.at_hotel_time(hotel: @booking.hotel, value: departure_date, kind: :check_out))
      Folios::SyncForecastedCharges.call(booking_folio: @booking.booking_folio) if @booking.booking_folio.present?
    end

    def post_early_checkout_charges(departure_date, old_check_out)
      Folios::PostEarlyCheckoutCharges.call(
        booking: @booking,
        folio: @booking.booking_folio,
        user: @user,
        departure_date: departure_date,
        original_check_out: old_check_out,
        options: @options
      )
    end

    def post_charge
      amount = @params[:charge_amount].to_d
      return failure("Charge amount must be greater than zero.") unless amount.positive?

      # The manual early-departure penalty follows the same billing route as the
      # room charges — to whatever folio that route targets, falling back to the
      # primary folio when unrouted.
      route = Folios::ResolveTargetFolio.call(
        booking: @booking,
        transaction_code: @booking.hotel.transaction_codes.find_by(system_key: "room_revenue")
      )
      return failure(route.error) unless route.success?

      Folios::PostCategoryCharge.call(
        folio: route.folio,
        user: @user,
        category: "early_departure_charge",
        amount: amount,
        description: "Early Departure Charge",
        options: @options
      )
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
