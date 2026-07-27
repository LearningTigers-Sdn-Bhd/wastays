# frozen_string_literal: true


module Folios
  module Lifecycle
    class CreateFolio
      include Authorizable

      PERMISSION = "manage_folio_windows"

      def self.call(booking:, user:, attributes: {}, skip_authorization: false)
        new(booking: booking, user: user, attributes: attributes, skip_authorization: skip_authorization).call
      end

      def initialize(booking:, user:, attributes: {}, skip_authorization: false)
        @booking = booking
        @hotel = booking.hotel
        @user = user
        @attributes = attributes.to_h.with_indifferent_access
        @skip_authorization = skip_authorization
      end

      def call
        return failure("You do not have permission to manage folio windows.") unless permitted?

        folio = nil
        BookingFolio.transaction do
          @booking.with_lock do
            NightAudits::OperationalChangeGuard.call!(hotel: @hotel, action: :create_folio)
            folio = @booking.booking_folios.create!(folio_attributes)
            log_operation!(folio)
            set_primary!(folio) if set_as_primary?
          end
        end

        success(folio)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages.to_sentence)
      rescue StandardError => e
        failure(e.message)
      end

      private

      def folio_attributes
        folio_number = DocumentIdentifiers::NextFolioNumber.call(hotel: @hotel)
        ensure_folio_account_reference!(folio_number)

        {
          hotel: @hotel,
          booking_room_id: @attributes[:booking_room_id].presence,
          folio_number: folio_number,
          folio_sequence: next_folio_sequence,
          label: @attributes[:label].presence,
          folio_type: @attributes[:folio_type].presence || "external",
          payer_type: @attributes[:payer_type].presence || "company",
          payer_id: @attributes[:payer_id].presence,
          booking_billing_party_id: @attributes[:booking_billing_party_id].presence,
          hotel_corporate_account_id: @attributes[:hotel_corporate_account_id].presence,
          is_primary: false,
          status: "open",
          currency: @attributes[:currency].presence || @booking.currency.presence || @hotel.default_currency,
          opened_at: Time.current,
          created_by: @user
        }
      end

      def ensure_folio_account_reference!(fallback_folio_number)
        return if @booking.folio_account_reference.present?

        base_folio = @booking.booking_folios.where.not(folio_number: nil).order(is_primary: :desc, created_at: :asc, id: :asc).first
        @booking.assign_folio_account_reference_from!(base_folio&.folio_number || fallback_folio_number)
      end

      def next_folio_sequence
        @booking.booking_folios.maximum(:folio_sequence).to_i + 1
      end

      def log_operation!(folio)
        FolioOperationLog.create!(
          hotel: @hotel,
          booking: @booking,
          actor: @user,
          operation_type: "create_folio",
          target_folio: folio,
          currency: folio.currency,
          reason: @attributes[:reason].presence,
          metadata: {
            label: folio.label,
            folio_type: folio.folio_type,
            payer_type: folio.payer_type,
            payer_id: folio.payer_id,
            hotel_corporate_account_id: folio.hotel_corporate_account_id,
            booking_room_id: folio.booking_room_id
          }
        )
      end

      def set_primary!(folio)
        reason = @attributes[:set_folio_as_primary_reason].to_s.strip.presence
        raise ActiveRecord::RecordInvalid.new(folio.tap { |record| record.errors.add(:base, "Reason for setting primary folio can't be blank.") }) if reason.blank?

        scope = @booking.booking_folios.where(booking_room_id: folio.booking_room_id)
        previous_primary = scope.where(is_primary: true).where.not(id: folio.id).first
        scope.where.not(id: folio.id).update_all(is_primary: false, updated_at: Time.current)
        folio.update!(is_primary: true)

        FolioOperationLog.create!(
          hotel: @hotel,
          booking: @booking,
          actor: @user,
          operation_type: "set_default_folio",
          source_folio: previous_primary,
          target_folio: folio,
          currency: folio.currency,
          reason: reason,
          metadata: {
            previous_primary_folio_id: previous_primary&.id,
            new_primary_folio_id: folio.id,
            booking_room_id: folio.booking_room_id
          }
        )
      end

      def set_as_primary?
        ActiveModel::Type::Boolean.new.cast(@attributes[:is_primary])
      end

      # skip_authorization is not a system bypass — the one caller
      # (BookingBillingParties::ManageCompany) passes a real staff actor who was
      # already gated on "manage_bookings" upstream. Creating the company's folio
      # is part of adding the billing party, so it deliberately does not demand
      # "manage_folio_windows" as well. The actor is still recorded on created_by.
      def permitted?
        return true if @skip_authorization

        actor_permits?(@user, PERMISSION, hotel: @hotel)
      end

      def success(folio)
        Folios::Lifecycle::Result.success(folio: folio)
      end

      def failure(error)
        Folios::Lifecycle::Result.failure(error)
      end
    end
  end
end
