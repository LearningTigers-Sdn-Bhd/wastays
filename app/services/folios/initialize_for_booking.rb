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
          Folios::GenerateForecastedCharges.call(booking_folio: folio)
        end

        folio
      end
    end

    def create_folio!
      folio_number = HotelCounter.increment!(hotel: @booking.hotel, type: "folio")
      @booking.assign_folio_account_reference_from!(folio_number)
      billing_party = agent_billing_party

      @booking.create_booking_folio!(
        hotel: @booking.hotel,
        folio_number: folio_number,
        folio_sequence: 1,
        name: billing_party ? "Agent Folio" : "Guest Folio",
        folio_type: billing_party ? "external" : "guest",
        payer_type: billing_party ? "company" : "guest",
        hotel_corporate_account: billing_party&.hotel_corporate_account,
        booking_billing_party: billing_party,
        is_primary: true,
        currency: @booking.currency.presence || @booking.hotel.default_currency,
        opened_at: Time.current,
        created_by: @user
      )
    end

    def agent_billing_party
      return unless @booking.hotel_corporate_account_id.present?

      hotel_corporate_account = @booking.hotel_corporate_account
      return unless hotel_corporate_account&.active?

      @booking.booking_billing_parties.find_or_create_by!(
        hotel_corporate_account: hotel_corporate_account
      ) do |party|
        party.hotel = @booking.hotel
        party.party_kind = "company"
        party.account_type = hotel_corporate_account.account_type
      end
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
