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

  def home_address
    safe_attr(:home_address).presence || "—"
  end

  def gender
    safe_attr(:gender)&.capitalize || "—"
  end

  def document_type
    safe_attr(:document_type)&.upcase || "—"
  end

  def formatted_name
    name&.titleize
  end

  def formatted_gender
    safe_attr(:gender)&.capitalize || "Unspecified"
  end

  def formatted_document_type
    legacy_document_label
  end

  def formatted_country
    safe_attr(:country) || "Unknown country"
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
    @guest.date_of_birth&.strftime("%d %b %Y") || "—"
  end

  # The caller passes the latest check-out date. Reading it from an unordered
  # scope returned an arbitrary booking, not the last stay.
  def last_stay_checkout_date(checkout_on)
    checkout_on&.strftime("%d %b %Y") || "—"
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

  def email_display
    email.presence || "—"
  end

  def phone_display
    phone.presence || "—"
  end

  def government_id_display
    government_id.presence || "—"
  end

  def country_display
    country.presence || "—"
  end

  def document_type_display
    formatted_document_type
  end

  def passport_number
    safe_attr(:passport_number).presence || "—"
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
