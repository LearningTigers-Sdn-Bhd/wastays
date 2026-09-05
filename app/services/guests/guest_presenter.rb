# frozen_string_literal: true

module Guests
  class GuestPresenter
    # The details tab is four blocks, each with its own Save. A block's copy is
    # written once here, because the first render and the re-render after a
    # save both need it, and `fields` decides what that block's save may write.
    SECTIONS = {
      "identity" => {
        title: "Guest identity",
        description: "Who the guest is, and how to reach them.",
        fields: %i[name email phone country gender date_of_birth]
      },
      "verification" => {
        title: "Identity verification",
        description: "Legal identification, as recorded at check-in.",
        fields: %i[document_type government_id passport_number]
      },
      "address" => {
        title: "Guest address",
        description: "Used on the folio and on an e-invoice.",
        fields: %i[home_address city state_code postal_code address_country]
      },
      "tax" => {
        title: "Tax management",
        description: "Needed only when the guest claims their stays.",
        fields: %i[tin]
      }
    }.freeze

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

    # The guest-identity controller swaps a national identity card for a MyKad
    # when the nationality is Malaysia, and back again when it is not. It ran
    # that swap on connect, which flipped the visible document type after the
    # page had already painted and woke the block's Save on load. The server
    # settles it first, so the controller finds nothing to change.
    #
    # The booking workspace reads the stay snapshot, not the profile, so this
    # is a class method too. Both callers settle the type the same way.
    def self.normalize_document_type(document_type, country)
      malaysian = country.to_s.casecmp?("malaysia")

      return "malaysian_nric" if malaysian && document_type == "national_id"
      return "national_id" if !malaysian && document_type == "malaysian_nric"

      document_type
    end

    # The label above the number field names the document in hand. It is
    # rendered here rather than rewritten in the browser, for the same reason.
    # Keep the wording in step with guest_identity_controller.js.
    def self.identity_number_label(document_type)
      case document_type
      when "passport" then "Passport number"
      when "national_id" then "National identity card number"
      when "malaysian_nric", "ic" then "MyKad number"
      else "Identity document number"
      end
    end

    def normalized_document_type
      self.class.normalize_document_type(safe_attr(:document_type), safe_attr(:country))
    end

    def identity_number_label
      self.class.identity_number_label(normalized_document_type)
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
