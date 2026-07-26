# frozen_string_literal: true

module FolioRouting
  # Bill a booking's room charges to a company billing party.
  #
  # Resolves/ensures the billing party and its folio, then delegates to the
  # kind-agnostic routing core to route room revenue onto that folio. The
  # guest's primary folio is never reassigned — it keeps incidentals and
  # tourism tax (which has no rule and therefore stays on the primary folio).
  #
  # Only company/government parties are wired today. Guest/agent parties slot
  # in as additional branches in `resolve_target_folio` with no change to the
  # routing core.
  class BillRoomChargesToCompany
    def self.call(booking:, actor:, hotel_corporate_account_id:, settlement_type: "cash_bank", bill_tourism_tax_to_company: false)
      new(booking: booking, actor: actor, hotel_corporate_account_id: hotel_corporate_account_id,
        settlement_type: settlement_type, bill_tourism_tax_to_company: bill_tourism_tax_to_company).call
    end

    def initialize(booking:, actor:, hotel_corporate_account_id:, settlement_type: "cash_bank", bill_tourism_tax_to_company: false)
      @booking = booking
      @actor = actor
      @hotel_corporate_account_id = hotel_corporate_account_id
      @settlement_type = settlement_type
      @bill_tourism_tax_to_company = ActiveModel::Type::Boolean.new.cast(bill_tourism_tax_to_company)
    end

    def call
      party_result = ensure_company_party
      return failure(party_result.error) unless party_result.success?

      party = party_result.party
      target_folio = folio_for(party)
      return failure("Bill-to party has no folio to receive room charges.") if target_folio.blank?

      room_code = room_revenue_code
      return failure("This hotel has no room revenue transaction code configured.") if room_code.blank?

      # Room charges always go to the billing party. Tourism tax stays on the
      # guest folio by default; only route it too when explicitly requested.
      codes = [ room_code ]
      codes << tourism_tax_code if @bill_tourism_tax_to_company && tourism_tax_code.present?

      codes.each do |code|
        route = RouteCodeToBillingParty.call(
          booking: @booking, transaction_code: code, target_folio: target_folio, actor: @actor
        )
        return failure(route.error) unless route.success?
      end

      BillingResult.success(party: party, target_folio: target_folio)
    end

    private

    def ensure_company_party
      BookingBillingParties::ManageCompany.call(
        booking: @booking, actor: @actor,
        attributes: { hotel_corporate_account_id: @hotel_corporate_account_id, settlement_type: @settlement_type }
      )
    end

    def folio_for(party)
      @booking.booking_folios.reload.find_by(booking_billing_party_id: party.id)
    end

    def room_revenue_code
      transaction_codes.room_revenue
    end

    def tourism_tax_code
      transaction_codes.for_key("tourism_tax")
    end

    def transaction_codes
      @transaction_codes ||= TransactionCodes::Resolver.for(@booking.hotel)
    end

    def failure(error) = BillingResult.failure(error)
  end
end
