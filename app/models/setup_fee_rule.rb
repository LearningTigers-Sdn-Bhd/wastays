class SetupFeeRule < ApplicationRecord
  belongs_to :settable, polymorphic: true, optional: true

  STATUSES = %w[active inactive].freeze
  CURRENCY = "MYR".freeze

  before_validation :normalize_target_fields

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :settable_type_must_be_blank_or_hotel
  validate :settable_id_presence_matches_target
  validate :single_active_global_default
  validate :single_active_hotel_override

  scope :active, -> { where(status: "active") }

  def active?
    status == "active"
  end

  private

  def settable_type_must_be_blank_or_hotel
    return if settable_type.blank? || settable_type == "Hotel"

    errors.add(:settable_type, "must be blank or Hotel")
  end

  def settable_id_presence_matches_target
    if settable_type == "Hotel" && settable_id.blank?
      errors.add(:settable_id, "must be present for hotel overrides")
    elsif settable_type.blank? && settable_id.present?
      errors.add(:settable_id, "must be blank for global defaults")
    end
  end

  def single_active_global_default
    return unless active? && settable_type.blank?

    scope = self.class.active.where(settable_type: nil, settable_id: nil)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:base, "Only one active global default setup fee is allowed.")
  end

  def single_active_hotel_override
    return unless active? && settable_type == "Hotel" && settable_id.present?

    scope = self.class.active.where(settable_type: "Hotel", settable_id: settable_id)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:base, "Only one active setup fee override is allowed per hotel.")
  end

  def normalize_target_fields
    self.settable_type = nil if settable_type.blank?
    self.settable_id = nil if settable_id.blank?
  end
end
