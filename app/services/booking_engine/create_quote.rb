require "ostruct"

module BookingEngine
  class CreateQuote
    def initialize(params)
      hotel_key = params[:hotel_id].to_s
      @hotel = Hotel.where(slug: hotel_key).first || Hotel.find(hotel_key)
      @room_type = @hotel.room_types.find(params[:room_type_id])
      @check_in = parse_date(params[:check_in])
      @check_out = parse_date(params[:check_out])
      @adults = (params[:adults].presence || 2).to_i
      @children = (params[:children].presence || 0).to_i
      @room_count = (params[:room_count].presence || 1).to_i
      @guest_name = params[:guest_name]
      @guest_email = params[:guest_email]
      @guest_phone = params[:guest_phone]
      @special_requests = params[:special_requests]
      @display_currency = CurrencyCatalog.normalize(params[:display_currency], fallback: nil)
      @rate_plan_id = params[:rate_plan_id]
    end

    def call
      validation_error = validate_dates
      return OpenStruct.new(success?: false, message: validation_error) if validation_error.present?

      BookingQuote.transaction do
        # 1. Revalidate availability one last time
        availability_service = BookingEngine::AvailabilityService.new(
          check_in: @check_in,
          check_out: @check_out,
          adults: @adults,
          children: @children,
          room_count: @room_count
        )

        available_rooms = availability_service.available_rooms_for_hotel(@hotel)
        unless available_rooms.include?(@room_type)
          return OpenStruct.new(success?: false, message: "Room is no longer available for these dates.")
        end

        # 2. Calculate total amount from the selected rate plan or lowest available.
        rate_plan = @rate_plan_id.present? ? @room_type.rate_plans.find_by(id: @rate_plan_id) : nil
        pricing_summary = availability_service.pricing_summary_for(@room_type, rate_plan: rate_plan)
        return OpenStruct.new(success?: false, message: "No valid rate is available for these dates.") if pricing_summary.blank?

        nightly_rates = pricing_summary[:nightly_rates]
        total_amount = pricing_summary[:total_price]
        quote_currency = pricing_summary[:currency]
        display_snapshot = display_snapshot_for(total_amount, quote_currency)

        # 3. Create Quote with snapshots
        quote = BookingQuote.new(
          hotel: @hotel,
          check_in: @check_in,
          check_out: @check_out,
          adults: @adults,
          children: @children,
          total_amount: total_amount,
          currency: quote_currency,
          display_currency: display_snapshot[:currency],
          display_total_amount: display_snapshot[:amount],
          display_exchange_rate: display_snapshot[:rate],
          display_rate_source: display_snapshot[:source],
          expires_at: 15.minutes.from_now,
          hotel_snapshot: @hotel.booking_snapshot,
          cancellation_policy_snapshot: @hotel.property_policy&.cancellation_policy,
          guest_name: @guest_name,
          guest_email: @guest_email,
          guest_phone: @guest_phone,
          special_requests: @special_requests
        )

        if quote.save
          # 4. Create Quote Item
          quote.booking_quote_items.create!(
            room_type: @room_type,
            quantity: @room_count,
            subtotal: total_amount,
            room_type_snapshot: @room_type.as_json,
            nightly_rate_snapshot: nightly_rates.transform_values(&:as_json),
            occupancy_snapshot: { max_adults: @room_type.max_adults, max_children: @room_type.max_children }
          )

          # Record Audit Log
          Bookings::RecordAuditLog.call(
            auditable: quote,
            action_type: "create"
          )

          # 5. Place Inventory Hold
          hold_service = BookingEngine::HoldInventory.new(quote)
          if hold_service.call
            OpenStruct.new(success?: true, quote: quote)
          else
            raise ActiveRecord::Rollback, "Failed to hold inventory"
          end
        else
          OpenStruct.new(success?: false, message: quote.errors.full_messages.to_sentence)
        end
      end
    rescue => e
      OpenStruct.new(success?: false, message: "An error occurred: #{e.message}")
    end

    private

    def parse_date(date_param)
      return date_param if date_param.is_a?(Date)
      return nil if date_param.blank?

      Date.parse(date_param)
    rescue ArgumentError
      nil
    end

    def validate_dates
      return "Please select check-in and check-out dates." if @check_in.blank? || @check_out.blank?
      return "Check-out date must be after check-in date." if @check_out <= @check_in

      nil
    end

    def display_snapshot_for(total_amount, quote_currency)
      display_currency = @display_currency.presence || quote_currency
      conversion = CurrencyConverter.convert(total_amount, from: quote_currency, to: display_currency, hotel: @hotel)
      return { currency: quote_currency, amount: total_amount, rate: 1.to_d, source: "charge_currency" } if conversion.blank?

      {
        currency: display_currency,
        amount: conversion.amount,
        rate: conversion.rate,
        source: conversion.source
      }
    end
  end
end
