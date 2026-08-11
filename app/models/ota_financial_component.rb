# frozen_string_literal: true

class OtaFinancialComponent < ApplicationRecord
  COMPONENT_KINDS = %w[accommodation fee service tax discount].freeze
  MAPPING_STATUSES = %w[mapped canonical unmapped].freeze
  RATE_TYPES = %w[percentage flat].freeze

  belongs_to :ota_financial_snapshot
  belongs_to :booking
  belongs_to :booking_room, optional: true
  belongs_to :transaction_code

  before_validation :normalize_identity_and_currencies
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  validates :component_kind, :stable_key, :stay_date, :provider_name,
    :normalized_provider_name, :original_currency, :currency, :mapping_status, presence: true
  validates :component_kind, inclusion: { in: COMPONENT_KINDS }
  validates :mapping_status, inclusion: { in: MAPPING_STATUSES }
  validates :rate_type, inclusion: { in: RATE_TYPES }, allow_nil: true
  validates :stable_key, uniqueness: { scope: %i[ota_financial_snapshot_id booking_id] }
  validates :original_currency, :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :original_amount, :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :gross_effect_amount, :posting_amount, :allocation_rounding_amount,
    numericality: true
  validates :rate, :basis_amount, numericality: true, allow_nil: true
  validates :metadata, exclusion: { in: [ nil ] }

  validate :accommodation_has_booking_room
  validate :amount_signs_match_component_kind
  validate :associations_share_financial_context

  private

  def normalize_identity_and_currencies
    self.normalized_provider_name = BookingSource.normalize(normalized_provider_name.presence || provider_name)
    self.normalized_provider_type = BookingSource.normalize(normalized_provider_type.presence || provider_type)
    self.original_currency = CurrencyCatalog.normalize(original_currency, fallback: nil)
    self.currency = CurrencyCatalog.normalize(currency, fallback: nil)
  end

  def accommodation_has_booking_room
    return unless component_kind == "accommodation" && booking_room.blank?

    errors.add(:booking_room, "is required for accommodation components")
  end

  def amount_signs_match_component_kind
    return if component_kind.blank? || gross_effect_amount.blank? || posting_amount.blank?

    expected_gross = if component_kind == "discount"
      gross_effect_amount <= 0
    elsif component_kind == "tax" && is_inclusive?
      gross_effect_amount.zero?
    else
      gross_effect_amount >= 0
    end
    errors.add(:gross_effect_amount, "has the wrong sign for #{component_kind}") unless expected_gross

    expected_posting = component_kind == "discount" ? posting_amount <= 0 : posting_amount >= 0
    errors.add(:posting_amount, "has the wrong sign for #{component_kind}") unless expected_posting
  end

  def associations_share_financial_context
    return if ota_financial_snapshot.blank? || booking.blank?

    if ota_financial_snapshot.booking_id.present?
      errors.add(:booking, "must match the snapshot booking") unless booking_id == ota_financial_snapshot.booking_id
    elsif booking.group_booking_id != ota_financial_snapshot.group_booking_id
      errors.add(:booking, "must belong to the snapshot group booking")
    end

    if booking.hotel_id != ota_financial_snapshot.hotel_id
      errors.add(:booking, "must belong to the snapshot hotel")
    end
    if booking_room.present? && booking_room.booking_id != booking_id
      errors.add(:booking_room, "must belong to the component booking")
    end
    if transaction_code.present? && transaction_code.hotel_id != ota_financial_snapshot.hotel_id
      errors.add(:transaction_code, "must belong to the snapshot hotel")
    end
  end

  def prevent_mutation
    errors.add(:base, "OTA financial components are immutable")
    throw :abort
  end
end
