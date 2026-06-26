# frozen_string_literal: true

module Guests
  class GuestPresenter
  def initialize(guest)
    @guest = guest
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

  private

  def safe_attr(attribute)
    @guest.public_send(attribute)
  rescue ActiveRecord::Encryption::Errors::Decryption
    "Encrypted data"
  end
  end
end
