# frozen_string_literal: true

class OtaFinancialComponentMapping < ApplicationRecord
  COMPONENT_KINDS = %w[fee service tax discount].freeze

  belongs_to :hotel
  belongs_to :booking_source, optional: true
  belongs_to :transaction_code
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_identity

  validates :provider, :component_kind, :normalized_provider_name, presence: true
  validates :component_kind, inclusion: { in: COMPONENT_KINDS }
  validates :normalized_provider_name, uniqueness: {
    scope: %i[hotel_id provider booking_source_id component_kind normalized_provider_type],
    case_sensitive: false
  }
  validate :booking_source_is_ota
  validate :transaction_code_belongs_to_hotel
  validate :transaction_code_kind_matches_component

  scope :active, -> { where(active: true) }

  private

  def normalize_identity
    self.provider = normalize(provider)
    self.normalized_provider_type = normalize(normalized_provider_type)
    self.normalized_provider_name = normalize(normalized_provider_name)
  end

  def normalize(value)
    BookingSource.normalize(value)
  end

  def booking_source_is_ota
    return if booking_source.blank? || booking_source.kind == "ota"

    errors.add(:booking_source, "must be an OTA source")
  end

  def transaction_code_belongs_to_hotel
    return if transaction_code.blank? || hotel.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def transaction_code_kind_matches_component
    return if transaction_code.blank? || component_kind.blank?

    expected_kind = { "tax" => "tax", "discount" => "adjustment" }.fetch(component_kind, "charge")
    return if transaction_code.kind == expected_kind

    errors.add(:transaction_code, "must be a #{expected_kind} code for #{component_kind} components")
  end
end
