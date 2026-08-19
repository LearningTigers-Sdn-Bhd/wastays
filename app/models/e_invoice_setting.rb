# frozen_string_literal: true

class EInvoiceSetting < ApplicationRecord
  belongs_to :hotel

  # The hotel's own MyInvois API credentials. WAStays is under the RM1m
  # threshold and so does not file as a supplier; it operates the submission on
  # the hotel's behalf using the hotel's own LHDN access.
  encrypts :client_id
  encrypts :client_secret
  encrypts :signing_private_key

  validate :signing_material_present, if: :signature_enabled?

  API_ENVIRONMENTS = %w[mock sandbox production].freeze

  validates :api_environment, inclusion: { in: API_ENVIRONMENTS }

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

  # Stamped the first time e-invoicing is switched on. Everything paid before
  # that point stays out of the feature entirely - enabling it must never
  # retroactively file, or consolidate, historical stays.
  before_save :stamp_effective_from, if: -> { enabled? && effective_from.blank? }

  def covers?(concluded_at)
    return false unless enabled?
    return false if concluded_at.blank?

    effective_from.blank? || concluded_at >= effective_from
  end

  # Filing needs both an identity to file as and access to file with.
  def signing_material_present
    return if signing_certificate.present? && signing_private_key.present?

    errors.add(:signature_enabled, "needs a signing certificate and private key before it can be switched on")
  end

  def api_credentials_ready?
    client_id.present? && client_secret.present?
  end

  def ready_to_file?
    enabled? && api_credentials_ready? && supplier_profile_ready?
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

  private

  def stamp_effective_from
    self.effective_from = Time.current
  end
end
