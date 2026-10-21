# frozen_string_literal: true

module Folios
  module Routing
    # Bill a travel agent booking's package to the agent: the room, plus every
    # extra charge the hotel includes in its travel agent packages (a jetty fee,
    # a boat transfer). Anything else, such as food and drinks, stays on the
    # guest's folio for them to settle at checkout.
    #
    # The room goes through BillRoomChargesToCompany, which makes the agent a
    # billing party with a folio; the package's extra charges are routed to that
    # same folio.
    class BillTravelAgentPackage
      def self.call(booking:, actor:, hotel_corporate_account_id:)
        new(booking:, actor:, hotel_corporate_account_id:).call
      end

      # The transaction codes that bill to the agent, room revenue first.
      def self.codes_for(hotel)
        room = TransactionCodes::Resolver.for(hotel).room_revenue
        [ room, *package_extra_codes(hotel) ].compact
      end

      def self.package_extra_codes(hotel)
        TransactionCode.joins(:hotel_extra_charge).active
          .where(hotel:, hotel_extra_charges: { bill_to_travel_agent: true })
          .order("hotel_extra_charges.position", :id).to_a
      end

      def initialize(booking:, actor:, hotel_corporate_account_id:)
        @booking = booking
        @actor = actor
        @hotel_corporate_account_id = hotel_corporate_account_id
      end

      def call
        room = BillRoomChargesToCompany.call(booking: @booking, actor: @actor, hotel_corporate_account_id: @hotel_corporate_account_id)
        return room unless room.success?

        extra_codes = self.class.package_extra_codes(@booking.hotel)
        extra_codes.each do |code|
          route = RouteCodeToBillingParty.call(booking: @booking, transaction_code: code, target_folio: room.target_folio, actor: @actor)
          return BillingResult.failure(route.error) unless route.success?
        end
        # An auto-applied extra was scheduled on the guest's folio when the
        # booking was made, and posts wherever it is scheduled.
        RerouteScheduledExtras.call(booking: @booking) if extra_codes.any?
        room
      end
    end
  end
end
