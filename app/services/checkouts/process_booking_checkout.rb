# frozen_string_literal: true

require "ostruct"

module Checkouts
  class ProcessBookingCheckout
    def self.call(booking:, hotel:, user:, timestamp:, folio_action_params:, posting_date:, early_departure_params: {}, checkout_options: {}, security_deposit_options: {})
      new(
        booking: booking,
        hotel: hotel,
        user: user,
        timestamp: timestamp,
        folio_action_params: folio_action_params,
        posting_date: posting_date,
        early_departure_params: early_departure_params,
        checkout_options: checkout_options,
        security_deposit_options: security_deposit_options
      ).call
    end

    def initialize(booking:, hotel:, user:, timestamp:, folio_action_params:, posting_date:, early_departure_params: {}, checkout_options: {}, security_deposit_options: {})
      @booking = booking
      @hotel = hotel
      @user = user
      @timestamp = timestamp
      @folio_action_params = folio_action_params.to_h
      @posting_date = posting_date
      @early_departure_params = early_departure_params.to_h
      @checkout_options = checkout_options.to_h
      @security_deposit_options = security_deposit_options.to_h
    end

    def call
      return failure("Check-out date and time can't be blank.") if @booking.checkout_required? && @timestamp.blank?

      early_result = process_early_departure_if_needed
      return early_result unless early_result.success?

      settlement_result = process_folio_actions
      return settlement_result unless settlement_result.success?

      transition_result = transition_to_completed(settlement_result)
      return transition_result unless transition_result.success?

      success
    end

    private

    def process_early_departure_if_needed
      return success unless early_departure_checkout?

      result = Bookings::ProcessEarlyDeparture.call(
        booking: @booking,
        user: @user,
        params: @early_departure_params,
        options: { timestamp: @timestamp, defer_checkout: true, defer_side_effects: true }
      )
      return failure(result.error) unless result.success?

      @booking.reload
      @booking.association(:booking_folio).reset
      success
    end

    def early_departure_checkout?
      @hotel.business_date_for(@timestamp.presence || Time.current).to_date < @booking.check_out.to_date
    end

    def process_folio_actions
      Folios::ProcessCheckoutActions.call(
        booking: @booking,
        hotel: @hotel,
        user: @user,
        action_params: @folio_action_params,
        posting_date: @posting_date,
        options: @checkout_options
      )
    end

    def transition_to_completed(settlement_result)
      Bookings::TransitionStatus.new(
        booking: @booking,
        status: "completed",
        timestamp: @timestamp,
        user: @user,
        options: {
          defer_side_effects: true,
          exception_folio_ids: settlement_result.exception_folio_ids.to_a,
          direct_bill_folio_ids: settlement_result.direct_bill_folio_ids.to_a
        }.merge(@checkout_options).merge(@security_deposit_options)
      ).call
    end

    def success
      OpenStruct.new(success?: true, error: nil, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, booking: @booking)
    end
  end
end
