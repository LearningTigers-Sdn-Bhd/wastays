module NightAudits
  module Evaluation
    module Warnings
      class UnusualFolioBalances
        def initialize(context:, folio_state: FolioState.new)
          @context = context
          @folio_state = folio_state
        end

        def call
          exceptions = in_house_bookings.filter_map { |booking| serialize_exception(booking) }
          exceptions.any? ? { "folio_balance_exceptions" => exceptions } : {}
        end

        private

        def in_house_bookings
          @context.hotel_bookings.checked_in.includes(booking_folio: :folio_transactions)
        end

        def serialize_exception(booking)
          return unless booking.booking_folio

          balance = @folio_state.outstanding_balance(booking.booking_folio)
          return unless balance > 1000.to_d || balance < -100.to_d

          {
            "booking_id" => booking.id,
            "confirmation_token" => booking.confirmation_token,
            "guest_name" => booking.guest_name,
            "status" => booking.status,
            "balance" => balance.to_f,
            "reason" => balance > 0 ? "Large outstanding balance" : "Large credit balance"
          }
        end
      end
    end
  end
end
