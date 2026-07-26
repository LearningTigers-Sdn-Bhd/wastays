# frozen_string_literal: true

require "ostruct"

module BookingBillingParties
  class ManageCompany
    class FolioCreationFailed < StandardError; end

    class GroupApplyFailed < StandardError
      attr_reader :booking

      def initialize(booking:, message:)
        @booking = booking
        super(message)
      end
    end

    def self.call(booking:, actor:, attributes:)
      new(booking: booking, actor: actor, attributes: attributes).call
    end

    def self.call_for_group(group_booking:, actor:, attributes:)
      parties = []
      ActiveRecord::Base.transaction do
        group_booking.lock!
        bookings = group_booking.bookings.order(:group_position, :id).to_a
        bookings.each(&:lock!)
        bookings.each do |booking|
          result = call(booking: booking, actor: actor, attributes: attributes)
          raise GroupApplyFailed.new(booking: booking, message: result.error) unless result.success?

          parties << result.party
        end
      end
      OpenStruct.new(success?: true, parties: parties, error: nil)
    rescue GroupApplyFailed => e
      reference = e.booking.formatted_reservation_number.presence || e.booking.id
      OpenStruct.new(success?: false, parties: [], error: "Booking No. #{reference}: #{e.message}")
    end

    def initialize(booking:, actor:, attributes:)
      @booking = booking
      @actor = actor
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      account = @booking.hotel.hotel_corporate_accounts.active.find_by(id: @attributes[:hotel_corporate_account_id])
      return failure("Select an active Company & Government Account.") unless account

      party = nil
      BookingBillingParty.transaction do
        party = @booking.booking_billing_parties.find_or_initialize_by(hotel_corporate_account: account)
        newly_created_or_reactivated = party.new_record? || party.archived_at.present?
        party.assign_attributes(hotel: @booking.hotel, party_kind: "company", archived_at: nil,
          account_type: @attributes[:account_type].presence || party.account_type || "company")
        party.created_by ||= @actor
        party.save!
        save_terms!(party)
        ensure_folio!(party) if newly_created_or_reactivated
        record_audit!(party)
      end
      success(party)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue FolioCreationFailed => e
      failure(e.message)
    end

    private

    def ensure_folio!(party)
      return if party.booking_folios.exists?

      result = Folios::Lifecycle::CreateFolio.call(
        booking: @booking,
        user: @actor,
        attributes: {
          folio_type: "external",
          payer_type: "company",
          booking_billing_party_id: party.id,
          hotel_corporate_account_id: party.hotel_corporate_account_id
        },
        skip_authorization: true
      )
      raise FolioCreationFailed, result.error unless result.success?
    end

    def save_terms!(party)
      terms = party.billing_terms || party.build_billing_terms(created_by: @actor)
      terms.assign_attributes(@attributes.slice(:settlement_type, :purchase_order_reference, :authorization_reference))
      terms.updated_by = @actor
      terms.save!
    end

    def record_audit!(party)
      BookingAuditLog.create!(hotel: @booking.hotel, auditable: @booking, user: @actor,
        action_type: "billing_party_added", category: "financial", source: "booking_workspace",
        occurred_at: Time.current, new_value: { billing_party_id: party.id, party: party.display_name })
    end

    def success(party) = OpenStruct.new(success?: true, party: party, error: nil)
    def failure(error) = OpenStruct.new(success?: false, party: nil, error: error)
  end
end
