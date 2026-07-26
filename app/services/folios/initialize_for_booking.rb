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
      # When unlocked we run inside the caller's transaction: a duplicate insert
      # would poison that transaction, so recovery is the caller's job, not ours.
      return initialize_folio unless @lock

      begin
        @booking.with_lock do
          initialize_folio
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # A concurrent caller inserted the primary folio between our existence
        # check and our insert — surfacing either as a DB unique violation or a
        # model uniqueness validation, depending on commit timing. Re-read and
        # hand back the winner's folio. If no folio actually exists, the error
        # was a genuine failure, so re-raise it untouched.
        @booking.reload
        existing = @booking.booking_folio
        raise if existing.blank?

        existing
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
          Folios::SyncForecastedCharges.call(booking_folio: folio)
        end

        folio
      end
    end

    def create_folio!
      Folios::BuildPrimaryFolio.call(booking: @booking, actor: @user, hotel: @booking.hotel)
    end

    def guard_folio_creation!
      return if system_initialization?

      NightAudits::OperationalChangeGuard.call!(
        hotel: @booking.hotel,
        action: :create_folio,
        night_audit: @options[:night_audit]
      )
    end

    # Confirmation is guest-facing and must not fail because staff started a
    # night audit. Creating the folio is safe to allow: it is empty at this
    # point, and SyncExistingPayments still runs the posting guards, so nothing
    # lands in the audited ledger. Keyed on the caller's system flag alone —
    # posting_source only labels the payment metadata and varies per caller.
    def system_initialization?
      @user.nil? && @options[:system_folio_initialization] == true
    end
  end
end
