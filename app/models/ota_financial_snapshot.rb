# frozen_string_literal: true

class OtaFinancialSnapshot < ApplicationRecord
  VARIANCE_REASONS = %w[
    fx_round_trip occupancy_difference channel_adjustment promotion unexplained
  ].freeze
  RECONCILIATION_STATUSES = %w[
    balanced balanced_with_rounding accepted_fx_variance unmapped_components
    total_mismatch rate_review_required
  ].freeze

  belongs_to :hotel
  belongs_to :booking_source, optional: true
  belongs_to :booking, optional: true
  belongs_to :group_booking, optional: true
  has_many :ota_financial_components, dependent: :restrict_with_error

  before_validation :normalize_provider_and_currencies
  before_update :prevent_financial_mutation
  before_destroy :prevent_destruction

  validates :provider, :channel_manager_reference, :provider_revision_id,
    :original_currency, :currency, :exchange_rate_source, :reconciliation_status, presence: true
  validates :provider_revision_id, uniqueness: {
    scope: %i[hotel_id provider channel_manager_reference]
  }
  validates :original_currency, :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :reconciliation_status, inclusion: { in: RECONCILIATION_STATUSES }
  validates :variance_reason, inclusion: { in: VARIANCE_REASONS }, allow_nil: true
  validates :original_gross_amount, :gross_amount, :original_accommodation_amount,
    :accommodation_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :expected_pms_accommodation_amount,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :exchange_rate, numericality: { greater_than: 0 }
  validates :conversion_rounding_amount, :mismatch_amount,
    numericality: true
  validates :variance_amount, :variance_percentage, numericality: true, allow_nil: true
  validates :policy_snapshot, :metadata, exclusion: { in: [ nil ] }

  validate :has_exactly_one_target
  validate :target_belongs_to_hotel

  scope :current, -> { where(current: true) }

  private

  def prevent_financial_mutation
    immutable_changes = changes_to_save.keys - %w[current superseded_at updated_at]
    return if immutable_changes.empty?

    errors.add(:base, "OTA financial snapshots are immutable")
    throw :abort
  end

  def prevent_destruction
    errors.add(:base, "OTA financial snapshots are immutable")
    throw :abort
  end

  def normalize_provider_and_currencies
    self.provider = BookingSource.normalize(provider)
    self.original_currency = CurrencyCatalog.normalize(original_currency, fallback: nil)
    self.currency = CurrencyCatalog.normalize(currency, fallback: nil)
  end

  def has_exactly_one_target
    return if booking.present? ^ group_booking.present?

    errors.add(:base, "must belong to exactly one booking or group booking")
  end

  def target_belongs_to_hotel
    target = booking || group_booking
    return if target.blank? || hotel.blank? || target.hotel_id == hotel_id

    errors.add(:base, "financial snapshot target must belong to the snapshot hotel")
  end
end
