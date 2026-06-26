# frozen_string_literal: true

require "ostruct"
require "securerandom"

module Folios
  class MoveForecast
    PERMISSION = "manage_folio_movements"

    def self.call(forecast:, target_folio:, user:, reason:)
      new(forecast: forecast, target_folio: target_folio, user: user, reason: reason).call
    end

    def initialize(forecast:, target_folio:, user:, reason:)
      @forecast = forecast
      @source_folio = forecast.booking_folio
      @target_folio = target_folio
      @booking = @source_folio.booking
      @hotel = @source_folio.hotel
      @user = user
      @reason = reason.to_s.strip
      @operation_key = SecureRandom.uuid
    end

    def call
      error = validate
      return failure(error) if error.present?

      ActiveRecord::Base.transaction do
        [ @source_folio, @target_folio ].sort_by(&:id).each(&:lock!)
        @forecast.lock!
        @forecast.update!(booking_folio: @target_folio)
        log_operation!
      end

      success(@forecast)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate
      return "You do not have permission to move folio forecasts." unless permitted?
      return "Move reason can't be blank." if @reason.blank?
      return "Forecast must be active." unless @forecast.status == "forecast"
      return "Source and target folios must be different." if @source_folio.id == @target_folio.id
      return "Source and target folios must belong to the same booking." unless @target_folio.booking_id == @booking.id
      return "Source and target folios must belong to the same hotel." unless @target_folio.hotel_id == @hotel.id
      return "Source folio must be open." unless @source_folio.open?
      return "Target folio must be open." unless @target_folio.open?

      nil
    end

    def log_operation!
      FolioOperationLog.create!(
        hotel: @hotel,
        booking: @booking,
        actor: @user,
        operation_type: "move_forecast",
        source_folio: @source_folio,
        target_folio: @target_folio,
        amount: @forecast.amount,
        currency: @target_folio.currency,
        operation_key: @operation_key,
        reason: @reason,
        metadata: {
          forecast_id: @forecast.id,
          stay_date: @forecast.stay_date&.iso8601,
          charge_kind: @forecast.charge_kind,
          identity: @forecast.identity
        }
      )
    end

    def permitted?
      @user&.respond_to?(:superadmin?) && @user.superadmin? ||
        @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
    end

    def success(forecast)
      OpenStruct.new(success?: true, forecast: forecast)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, forecast: @forecast)
    end
  end
end
