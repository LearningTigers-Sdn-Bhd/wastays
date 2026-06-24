# frozen_string_literal: true

require "ostruct"

module Folios
  class CreateFolio
    PERMISSION = "manage_folio_windows"

    def self.call(booking:, user:, attributes: {})
      new(booking: booking, user: user, attributes: attributes).call
    end

    def initialize(booking:, user:, attributes: {})
      @booking = booking
      @hotel = booking.hotel
      @user = user
      @attributes = attributes.to_h.with_indifferent_access
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
      folio_number = HotelCounter.increment!(hotel: @hotel, type: "folio")
      ensure_folio_account_reference!(folio_number)

      {
        hotel: @hotel,
        folio_number: folio_number,
        folio_sequence: next_folio_sequence,
        name: @attributes[:name].presence || default_name,
        folio_type: @attributes[:folio_type].presence || "external",
        payer_type: @attributes[:payer_type].presence || "company",
        payer_id: @attributes[:payer_id].presence,
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

    def default_name
      case @attributes[:folio_type].to_s
      when "guest" then "Guest Folio"
      when "house" then "House Folio"
      else "External Folio"
      end
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
          name: folio.name,
          folio_type: folio.folio_type,
          payer_type: folio.payer_type,
          payer_id: folio.payer_id,
          hotel_corporate_account_id: folio.hotel_corporate_account_id
        }
      )
    end

    def set_primary!(folio)
      reason = @attributes[:set_folio_as_primary_reason].to_s.strip.presence
      raise ActiveRecord::RecordInvalid.new(folio.tap { |record| record.errors.add(:base, "Reason for setting primary folio can't be blank.") }) if reason.blank?

      previous_primary = @booking.booking_folios.where(is_primary: true).where.not(id: folio.id).first
      @booking.booking_folios.where.not(id: folio.id).update_all(is_primary: false, updated_at: Time.current)
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
          new_primary_folio_id: folio.id
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
      OpenStruct.new(success?: false, error: error, folio: nil)
    end
  end
end
