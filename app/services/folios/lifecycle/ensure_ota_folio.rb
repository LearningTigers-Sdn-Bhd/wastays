# frozen_string_literal: true

module Folios
  module Lifecycle
    # Idempotently materializes the folio identity used for OTA-collected
    # bookings.  A booking always keeps its ordinary primary folio; OTA room
    # revenue is routed to a separate, non-primary external folio.
    class EnsureOtaFolio
      def self.call!(booking:, booking_source:, actor: nil)
        new(booking:, booking_source:, actor:).call!
      end

      def self.call(...)
        call!(...)
      end

      def initialize(booking:, booking_source:, actor: nil)
        @booking = booking
        @booking_source = booking_source
        @actor = actor
      end

      def call!
        validate!

        folio = nil
        BookingFolio.transaction do
          @booking.with_lock do
            ensure_primary_folio!
            party = BookingBillingParties::EnsureOta.call!(
              booking: @booking, booking_source: @booking_source, actor: @actor
            )
            folio = find_ota_folio(party)
            folio ||= create_ota_folio!(party)
            normalize_currency!(folio)
            ensure_room_revenue_route!(folio)
          end
        end
        folio
      rescue ActiveRecord::RecordNotUnique
        # A unique folio/party insert can race with a webhook that acquired the
        # booking lock just before this transaction.  Re-read the canonical row.
        @booking.reload
        party = @booking.booking_billing_parties.active.find_by(booking_source_id: @booking_source.id)
        folio = party&.booking_folios&.where(folio_type: "external", payer_type: "ota", is_primary: false)&.order(:id)&.first
        raise unless folio

        normalize_currency!(folio)
        ensure_room_revenue_route!(folio)
        folio
      end

      private

      def validate!
        raise ArgumentError, "Booking is required." unless @booking.is_a?(Booking) && @booking.persisted?
        raise ArgumentError, "Booking must belong to a hotel." if @booking.hotel_id.blank?
        unless @booking_source.is_a?(BookingSource) && @booking_source.persisted?
          raise ArgumentError, "Booking source is required."
        end
        if @booking_source.respond_to?(:hotel_id) && @booking_source.hotel_id.present? &&
            @booking_source.hotel_id != @booking.hotel_id
          raise ArgumentError, "Booking source must belong to the booking hotel."
        end
        return if @booking_source.kind == "ota"

        raise ArgumentError, "Booking source must be an OTA booking source."
      end

      def ensure_primary_folio!
        @booking.association(:booking_folio).reset
        return @booking.booking_folio if @booking.booking_folio.present?

        # This is a system/webhook initialization.  Keeping it in the existing
        # lifecycle service preserves payment/forecast synchronization while the
        # caller owns the booking lock.
        Folios::Lifecycle::InitializeForBooking.call(
          booking: @booking,
          user: @actor,
          options: { system_folio_initialization: true },
          lock: false
        )
        @booking.association(:booking_folio).reset
        @booking.booking_folio || raise("Booking primary folio could not be initialized.")
      end

      def find_ota_folio(party)
        party.booking_folios
          .where(folio_type: "external", payer_type: "ota", is_primary: false)
          .order(:id)
          .lock
          .first
      end

      def create_ota_folio!(party)
        result = Folios::Lifecycle::CreateFolio.call(
          booking: @booking,
          user: @actor,
          skip_authorization: true,
          attributes: {
            folio_type: "external",
            payer_type: "ota",
            booking_billing_party_id: party.id,
            currency: @booking.hotel.default_currency.presence || @booking.currency
          }
        )
        return result.folio if result.success?

        raise result.error.to_s
      end

      def normalize_currency!(folio)
        expected = @booking.hotel.default_currency.presence || @booking.currency
        return folio if folio.currency == expected

        folio.update!(currency: expected)
        folio
      end

      def ensure_room_revenue_route!(folio)
        room_revenue = TransactionCodes::Resolver.for(@booking.hotel).room_revenue
        return unless room_revenue

        existing = @booking.folio_routing_rules.active.find_by(transaction_code_id: room_revenue.id)
        # Never steal a deliberate staff route.  An OTA folio is the intended
        # target only when this service owns the route (or it already points at
        # the canonical OTA folio).
        return existing if existing && existing.target_folio_id != folio.id

        result = Folios::Routing::RouteCodeToBillingParty.call(
          booking: @booking,
          transaction_code: room_revenue,
          target_folio: folio,
          actor: @actor
        )
        raise result.error unless result.success?

        result.rule
      end
    end
  end
end
