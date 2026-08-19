# frozen_string_literal: true

class EInvoiceSetting < ApplicationRecord
  belongs_to :hotel

  COUNTRY_CODE_MAP = {
    "malaysia" => "MYS"
  }.freeze

  validates :hotel_tin,
    format: { with: /\A[A-Z]{1,2}\d+\z/, message: "must be a valid TIN (e.g. C1234567890)" },
    allow_blank: true
  validates :hotel_brn, length: { maximum: 20 }, allow_blank: true
  validates :supplier_contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  with_options if: :intermediary_enabled? do
    validates :hotel_tin, :hotel_brn, :supplier_msic_code, :supplier_business_description,
      :supplier_address_line1, :supplier_city, :supplier_postal_code, :supplier_state_code,
      :supplier_contact_phone, :supplier_contact_email, presence: true
  end

  def buyer_configured?
    hotel_tin.present? && hotel_brn.present?
  end

  def supplier_profile_ready?
    hotel_tin.present? &&
      hotel_brn.present? &&
      supplier_msic_code.present? &&
      supplier_business_description.present? &&
      supplier_address_line1.present? &&
      supplier_city.present? &&
      supplier_postal_code.present? &&
      supplier_state_code.present? &&
      supplier_contact_phone.present? &&
      supplier_contact_email.present?
  end

  def intermediary_ready?
    intermediary_enabled? && supplier_profile_ready?
  end

  def supplier_name
    hotel.name
  end

  def supplier_address_line1_value
    supplier_address_line1.presence || hotel.address
  end

  def supplier_address_line2_value
    supplier_address_line2
  end

  def supplier_city_value
    supplier_city.presence || hotel.city
  end

  def supplier_country_code_value
    supplier_country_code.presence || COUNTRY_CODE_MAP.fetch(hotel.country.to_s.strip.downcase, "MYS")
  end

  def supplier_contact_phone_value
    supplier_contact_phone.presence || hotel.contact_phone
  end

  def supplier_contact_email_value
    supplier_contact_email.presence || hotel.contact_email
  end
end
