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

  private

  def safe_attr(attribute)
    @guest.public_send(attribute)
  rescue ActiveRecord::Encryption::Errors::Decryption
    "Encrypted data"
  end
  end
end
