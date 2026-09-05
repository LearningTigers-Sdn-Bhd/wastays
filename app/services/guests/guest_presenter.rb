# frozen_string_literal: true

module Guests
  class GuestPresenter
    attr_reader :guest

    delegate :vip?, :repeat?, to: :guest

    def initialize(guest)
      @guest = guest
    end

    def blacklisted?(hotel = nil)
      @guest.blacklisted?(hotel: hotel)
    end

    # Every reader below returns nil when the guest has no value. The view
    # decides how a gap looks — see ApplicationHelper#blank_value. A presenter
    # that returned "—" left callers unable to ask whether a value exists.
    def name
      safe_attr(:name)
    end

    def email
      safe_attr(:email)
    end

    def phone
      safe_attr(:phone)
    end

    def government_id
      safe_attr(:government_id)
    end

    def country
      safe_attr(:country)
    end

    def passport_number
      safe_attr(:passport_number).presence
    end

    def formatted_name
      name&.titleize
    end

    def formatted_gender
      safe_attr(:gender).presence&.capitalize
    end

    # A label for the number the guest handed over, not a value. It always
    # names a document type, so it never falls back to a blank state.
    def formatted_document_type
      legacy_document_label
    end

    def formatted_country
      safe_attr(:country).presence
    end

    def last_stay_time
      @guest.try(:last_stay_at)&.strftime("%I:%M %p")
    end

    def last_stay_date
      @guest.try(:last_stay_at)&.strftime("%d %b %Y")
    end

    def last_stay_present?
      @guest.try(:last_stay_at).present?
    end

    def date_of_birth_formatted
      @guest.date_of_birth&.strftime("%d %b %Y")
    end

    # The caller passes the latest check-out date. Reading it from an unordered
    # scope returned an arbitrary booking, not the last stay.
    def last_stay_checkout_date(checkout_on)
      checkout_on&.strftime("%d %b %Y")
    end

    def formatted_currency_amount(amount, currency)
      CurrencyFormatter.format(amount, currency: currency, unit: :code)
    end

    def formatted_stays_count(count)
      ActionController::Base.helpers.pluralize(count, "stay")
    end

    def formatted_currency_totals(totals)
      return [] if totals.blank?

      totals.map { |currency, amount| CurrencyFormatter.format(amount, currency: currency, unit: :code) }
    end

    # A foreign guest with a national identity card needs a passport number
    # before the hotel can issue an individual e-invoice.
    def passport_status
      return unless @guest.lhdn_passport_required?

      safe_attr(:passport_number).present? ? "Passport on file" : "Passport needed"
    end

    private

    def legacy_document_label
      case safe_attr(:document_type)
      when "ic", "malaysian_nric" then "MyKad"
      when "national_id" then "National identity card"
      when "passport" then "Passport"
      else "Identity document"
      end
    end

    def safe_attr(attribute)
      @guest.public_send(attribute)
    rescue ActiveRecord::Encryption::Errors::Decryption
      "Encrypted data"
    end
  end
end
