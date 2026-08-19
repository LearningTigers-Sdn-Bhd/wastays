# frozen_string_literal: true

require "ostruct"

module Bookings
  class UpdateGuestRegistrationCard
    def self.call(card:, booking:, params:, booking_guest_id: nil)
      new(card: card, booking: booking, params: params, booking_guest_id: booking_guest_id).call
    end

    def initialize(card:, booking:, params:, booking_guest_id: nil)
      @card = card
      @booking = booking
      @params = params.to_h.deep_symbolize_keys
      @booking_guest_id = booking_guest_id
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
          break :already_signed if @card.signed_for_guest?(@booking_guest_id)
          break :terms_missing unless @card.hotel.guest_registration_card_terms.present?

          if @params[:signature_data_url].blank?
            @card.errors.add(:signature_data_url, "can't be blank")
            break :invalid
          end

          @card.save_signature_for_guest!(
            booking_guest_id: @booking_guest_id,
            signer_name: @params[:signer_name],
            signature_data_url: @params[:signature_data_url]
          )
          :saved
        end

        case result
        when :already_signed
          return OpenStruct.new(success?: false, error: :already_signed, message: "Delete the existing signature before signing again.")
        when :terms_missing
          return OpenStruct.new(success?: false, error: :terms_missing, message: "This property hasn't set its Terms & Conditions yet. An admin needs to add them in Settings before this card can be signed.")
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
