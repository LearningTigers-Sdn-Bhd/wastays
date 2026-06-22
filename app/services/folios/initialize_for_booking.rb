# frozen_string_literal: true

module Folios
  class InitializeForBooking
    def self.call(booking:, user:, options: {}, lock: true)
      new(booking: booking, user: user, options: options, lock: lock).call
    end

    def initialize(booking:, user:, options: {}, lock: true)
      @booking = booking
      @user = user
      @options = options
      @lock = lock
    end

    def call
      return initialize_folio unless @lock

      @booking.with_lock do
        initialize_folio
      end
    end

    private

    def initialize_folio
      BookingFolio.transaction do
        @booking.association(:booking_folio).reset
        folio = @booking.booking_folio

        unless folio.present?
          guard_folio_creation!
          folio = create_folio!

          Folios::SyncExistingPayments.call(folio: folio, user: @user, options: @options)
          Folios::GenerateForecastedCharges.call(booking_folio: folio)
        end

        folio
      end
    end

    def create_folio!
      folio_number = HotelCounter.increment!(hotel: @booking.hotel, type: "folio")
      @booking.create_booking_folio!(hotel: @booking.hotel, folio_number: folio_number)
    end

    def guard_folio_creation!
      return if system_confirmation_initialization?

      NightAudits::OperationalChangeGuard.call!(
        hotel: @booking.hotel,
        action: :create_folio,
        night_audit: @options[:night_audit]
      )
    end

    def system_confirmation_initialization?
      @user.nil? &&
        @options[:system_folio_initialization] == true &&
        @options[:posting_source] == "booking_confirmation"
    end
  end
end
