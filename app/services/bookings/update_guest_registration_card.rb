# frozen_string_literal: true

require "ostruct"

module Bookings
  class UpdateGuestRegistrationCard
    def self.call(card:, booking:, params:)
      new(card: card, booking: booking, params: params).call
    end

    def initialize(card:, booking:, params:)
      @card = card
      @booking = booking
      @params = params.to_h.deep_symbolize_keys
    end

    def call
      # 1. Update booking attributes if present
      booking_params = @params.slice(:special_requests, :internal_notes)
      if booking_params.present?
        @booking.update!(booking_params)
      end

      # 2. If signature params are present
      if @params[:signer_name].present? || @params[:signature_data_url].present?
        result = @card.with_lock do
          break :already_signed if @card.signed?

          if @params[:signature_data_url].blank?
            @card.errors.add(:signature_data_url, "can't be blank")
            break :invalid
          end

          @card.assign_attributes(
            signer_name: @params[:signer_name],
            signature_data_url: @params[:signature_data_url],
            status: "signed",
            signed_at: Time.current,
            terms_snapshot: @card.capture_terms_snapshot_preview,
            display_fields_snapshot: @card.capture_display_fields_snapshot
          )
          @card.save ? :saved : :invalid
        end

        case result
        when :already_signed
          return OpenStruct.new(success?: false, error: :already_signed, message: "Delete the existing signature before signing again.")
        when :invalid
          return OpenStruct.new(success?: false, error: :invalid, message: @card.errors.full_messages.to_sentence)
        end
      end

      OpenStruct.new(success?: true)
    rescue ActiveRecord::RecordInvalid => e
      OpenStruct.new(success?: false, error: :invalid, message: e.record.errors.full_messages.to_sentence)
    end
  end
end
