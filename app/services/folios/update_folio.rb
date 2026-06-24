# frozen_string_literal: true

require "ostruct"

module Folios
  class UpdateFolio
    PERMISSION = "manage_folio_windows"

    def self.call(folio:, user:, attributes: {})
      new(folio: folio, user: user, attributes: attributes).call
    end

    def initialize(folio:, user:, attributes: {})
      @folio = folio
      @booking = folio.booking
      @hotel = folio.hotel
      @user = user
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      return failure("You do not have permission to manage folio windows.") unless permitted?
      return failure("Closed or voided folios cannot be edited.") unless @folio.open?

      BookingFolio.transaction do
        @booking.with_lock do
          @folio.lock!
          @folio.reload
          NightAudits::OperationalChangeGuard.call!(hotel: @hotel, action: :update_folio)

          previous_name = @folio.name
          previous_folio_type = @folio.folio_type
          previous_payer_type = @folio.payer_type
          previous_payer_id = @folio.payer_id
          previous_hotel_corporate_account_id = @folio.hotel_corporate_account_id

          @folio.update!(folio_attributes)
          log_update!(previous_name, previous_folio_type, previous_payer_type, previous_payer_id, previous_hotel_corporate_account_id)
          set_primary! if set_as_primary? && !@folio.is_primary?
        end
      end

      success(@folio.reload)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def folio_attributes
      {
        name: @attributes[:name],
        folio_type: @attributes[:folio_type],
        payer_type: @attributes[:payer_type],
        payer_id: @attributes[:payer_id].presence,
        hotel_corporate_account_id: @attributes[:hotel_corporate_account_id].presence,
        currency: @attributes[:currency]
      }.compact
    end

    def log_update!(previous_name, previous_folio_type, previous_payer_type, previous_payer_id, previous_hotel_corporate_account_id)
      changes = {
        name: [ previous_name, @folio.name ],
        folio_type: [ previous_folio_type, @folio.folio_type ],
        payer_type: [ previous_payer_type, @folio.payer_type ],
        payer_id: [ previous_payer_id, @folio.payer_id ],
        hotel_corporate_account_id: [ previous_hotel_corporate_account_id, @folio.hotel_corporate_account_id ]
      }.select { |_key, (before, after)| before != after }
      return if changes.empty?

      FolioOperationLog.create!(
        hotel: @hotel,
        booking: @booking,
        actor: @user,
        operation_type: "rename_folio",
        source_folio: @folio,
        target_folio: @folio,
        reason: @attributes[:reason].presence,
        currency: @folio.currency,
        metadata: { changes: changes.transform_values { |before, after| { from: before, to: after } } }
      )
    end

    def set_primary!
      reason = @attributes[:set_folio_as_primary_reason].to_s.strip.presence
      @folio.errors.add(:base, "Reason for setting primary folio can't be blank.")
      raise ActiveRecord::RecordInvalid.new(@folio) if reason.blank?

      previous_primary = @booking.booking_folios.where(is_primary: true).where.not(id: @folio.id).first
      @booking.booking_folios.where.not(id: @folio.id).update_all(is_primary: false, updated_at: Time.current)
      @folio.update!(is_primary: true)

      FolioOperationLog.create!(
        hotel: @hotel,
        booking: @booking,
        actor: @user,
        operation_type: "set_default_folio",
        source_folio: previous_primary,
        target_folio: @folio,
        currency: @folio.currency,
        reason: reason,
        metadata: {
          previous_primary_folio_id: previous_primary&.id,
          new_primary_folio_id: @folio.id
        }
      )
    end

    def set_as_primary?
      ActiveModel::Type::Boolean.new.cast(@attributes[:is_primary])
    end

    def permitted?
      @user&.respond_to?(:superadmin?) && @user.superadmin? ||
        @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
    end

    def success(folio)
      OpenStruct.new(success?: true, folio: folio)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, folio: @folio)
    end
  end
end
