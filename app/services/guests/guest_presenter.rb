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
    safe_attr(:document_type)&.upcase || "ID"
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

  def last_stay_checkout_date(all_bookings)
    all_bookings.first&.check_out&.strftime("%d %b %Y") || "—"
  end

  def formatted_currency_amount(amount, currency)
    unit = (currency == "USD" ? "USD " : "RM ")
    ActionController::Base.helpers.number_to_currency(amount, unit: unit, delimiter: ",")
  end

  def formatted_stays_count(count)
    ActionController::Base.helpers.pluralize(count, "stay")
  end

  def formatted_currency_totals(totals)
    return [] if totals.blank?

    totals.map do |currency, amount|
      "#{currency} #{ActionController::Base.helpers.number_with_precision(amount, precision: 2, delimiter: ",")}"
    end
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
    safe_attr(:document_type)&.upcase || "IC/PASSPORT"
  end

  private

  def safe_attr(attribute)
    @guest.public_send(attribute)
  rescue ActiveRecord::Encryption::Errors::Decryption
    "Encrypted data"
  end
  end
end
