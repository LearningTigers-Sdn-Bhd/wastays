# frozen_string_literal: true

require "ostruct"

module Folios
  class RecoverMissingFolio
    BLOCKER_TYPE = "missing_folio"
    POSTING_SOURCE = "audit_blocker_resolution"

    def self.call(booking:, hotel:, actor:, night_audit:, reason:)
      new(booking: booking, hotel: hotel, actor: actor, night_audit: night_audit, reason: reason).call
    end

    def initialize(booking:, hotel:, actor:, night_audit:, reason:)
      @booking = booking
      @hotel = hotel
      @actor = actor
      @night_audit = night_audit
      @reason = reason.to_s.strip.presence || "Recover missing booking folio from Night Audit blocker resolution."
    end

    def call
      return failure("Booking does not belong to this hotel.") unless @booking.hotel_id == @hotel.id
      return failure("Night Audit does not belong to this hotel.") unless @night_audit.hotel_id == @hotel.id

      created = false
      folio = nil

      @booking.with_lock do
        BookingFolio.transaction do
          @booking.association(:booking_folio).reset
          folio = @booking.booking_folio

          unless folio
            folio = create_folio!
            created = true
          end

          Folios::SyncForecastedCharges.call(booking_folio: folio)
        end
      end

      record_recovery_event!(folio: folio, created: created)
      success(folio: folio, created: created)
    rescue ActiveRecord::RecordNotUnique
      @booking.reload
      folio = @booking.booking_folio
      if folio
        record_recovery_event!(folio: folio, created: false)
        return success(folio: folio, created: false)
      end

      failure("Could not recover missing folio because another process modified the booking.")
    rescue StandardError => e
      failure(e.message)
    end

    private

    def create_folio!
      folio_number = Folios::NextFolioNumber.call(hotel: @hotel)
      @booking.assign_folio_account_reference_from!(folio_number)
      @booking.create_booking_folio!(
        hotel: @hotel,
        folio_number: folio_number,
        folio_sequence: 1,
        status: "open",
        name: "Guest Folio",
        folio_type: "guest",
        payer_type: "guest",
        is_primary: true,
        currency: @booking.currency.presence || @hotel.default_currency,
        opened_at: Time.current,
        created_by: @actor
      )
    end

    def record_recovery_event!(folio:, created:)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: @night_audit.business_date,
        event_type: "missing_folio_recovered",
        source: POSTING_SOURCE,
        actor: @actor,
        booking_folio: folio,
        booking: @booking,
        night_audit: @night_audit,
        hotel_business_date: @hotel.current_business_date_record,
        reason: @reason,
        metadata: {
          blocker_type: BLOCKER_TYPE,
          created: created,
          actor_id: @actor&.id,
          hotel_id: @hotel.id,
          booking_id: @booking.id,
          booking_folio_id: folio.id,
          night_audit_id: @night_audit.id,
          business_date: @night_audit.business_date.iso8601,
          reason: @reason
        }
      )
    end

    def success(folio:, created:)
      OpenStruct.new(success?: true, folio: folio, created?: created, message: created ? "Folio recovered." : "Folio already exists.")
    end

    def failure(error)
      OpenStruct.new(success?: false, folio: nil, created?: false, error: error, message: error)
    end
  end
end
