# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  FOLIO_TYPES = %w[guest company custom group master house].freeze
  PAYER_TYPES = %w[guest company custom].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :folio_transactions, dependent: :restrict_with_error
  has_many :folio_forecasted_charges, dependent: :destroy
  has_many :deposits, dependent: :restrict_with_error
  has_many :financial_audit_events, dependent: :restrict_with_error
  has_many :source_operation_logs, class_name: "FolioOperationLog", foreign_key: :source_folio_id, dependent: :restrict_with_error
  has_many :target_operation_logs, class_name: "FolioOperationLog", foreign_key: :target_folio_id, dependent: :restrict_with_error

  enum :status, { open: "open", closed: "closed", voided: "voided" }, validate: true
  enum :folio_type, FOLIO_TYPES.index_by(&:itself), prefix: true, validate: true
  enum :payer_type, PAYER_TYPES.index_by(&:itself), prefix: true, validate: true

  validates :folio_number, presence: true, uniqueness: { scope: :hotel_id }
  validates :name, presence: true
  validates :currency, presence: true
  validates :opened_at, presence: true
  validates :status, presence: true
  validates :invoice_number, uniqueness: { scope: :hotel_id, allow_nil: true }
  validates :folio_sequence, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :folio_sequence, uniqueness: { scope: :booking_id, allow_nil: true }
  validates :is_primary, uniqueness: { scope: :booking_id, conditions: -> { where(is_primary: true) }, if: :is_primary? }
  validate :hotel_matches_booking
  validate :closed_folio_reopen_must_be_authorized
  validate :last_primary_folio_cannot_be_unset
  validate :closed_folio_fields_are_restricted, on: :update
  before_validation :assign_defaults
  after_create :ensure_booking_folio_account_reference
  before_destroy :guard_night_audit_operational_change
  before_destroy :prevent_destroying_last_folio

  def outstanding_balance
    total_charges - total_payments + total_adjustments
  end

  def unsettled_forecasts
    folio_forecasted_charges.forecast
  end

  def projected_forecasts
    return folio_forecasted_charges.none if status == "closed" || booking.blank?
    return folio_forecasted_charges.none if booking.status.in?(%w[cancelled completed no_show])

    unsettled_forecasts
      .where(FolioForecastedCharge.arel_table[:stay_date].lt(booking.check_out.to_date))
      .order(:stay_date, :charge_kind, :identity)
  end

  def all_charges_posted?
    folio_forecasted_charges.forecast.none?
  end

  def projected_outstanding_balance
    outstanding_balance + projected_forecasts.sum(:amount)
  end

  def display_name
    name.presence || (is_primary? ? "Guest Folio" : "Folio #{folio_number}")
  end

  def display_option_label
    [ display_name, folio_reference_display ].compact_blank.join(" · ")
  end

  def account_reference
    booking&.folio_account_reference_display
  end

  def folio_reference_display
    reference = account_reference.presence
    sequence = folio_sequence.presence
    return "#{reference}/#{sequence}" if reference.present? && sequence.present?
    return reference if reference.present?

    folio_number.presence || booking&.confirmation_token
  end

  def active_for_operations?
    open?
  end

  def total_charges
    folio_transactions.charge.sum(:amount)
  end

  def total_payments
    folio_transactions.payment.sum(:amount)
  end

  def total_adjustments
    folio_transactions.adjustment.sum(:amount)
  end

  private

  def guard_night_audit_operational_change
    NightAudits::OperationalChangeGuard.call!(hotel: hotel, action: :remove_folio)
  end

  def assign_defaults
    self.name = "Guest Folio" if name.blank? && is_primary?
    self.name = "Folio #{folio_number}" if name.blank? && folio_number.present?
    self.folio_type ||= "guest"
    self.payer_type ||= "guest"
    self.currency ||= booking&.currency.presence || hotel&.default_currency.presence || "MYR"
    self.opened_at ||= Time.current
    self.folio_sequence ||= next_folio_sequence if booking.present?
  end

  def next_folio_sequence
    scope = booking.booking_folios
    scope = scope.where.not(id: id) if persisted?
    scope.maximum(:folio_sequence).to_i + 1
  end

  def hotel_matches_booking
    return if hotel_id.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end

  def closed_folio_reopen_must_be_authorized
    return unless will_save_change_to_status?
    return unless status_in_database == "closed" && status == "open"
    return if @reopen_for_correction_authorized

    errors.add(:status, "can only be reopened through the controlled correction workflow")
  end

  def last_primary_folio_cannot_be_unset
    return unless persisted? && will_save_change_to_is_primary? && !is_primary?
    return if booking.blank?
    return if booking.booking_folios.where.not(id: id).where(is_primary: true).exists?

    errors.add(:is_primary, "must remain set until another primary folio exists")
  end

  def closed_folio_fields_are_restricted
    return unless status_in_database.in?(%w[closed voided])
    return if will_save_change_to_status?

    allowed = %w[updated_at]
    changed = changes.keys - allowed
    return if changed.empty?

    errors.add(:base, "Closed or voided folios cannot be edited through the normal workflow.")
  end

  def prevent_destroying_last_folio
    return if booking.blank?
    return if booking.booking_folios.where.not(id: id).exists?

    errors.add(:base, "Cannot delete the last folio for a booking.")
    throw :abort
  end

  def ensure_booking_folio_account_reference
    return if booking.blank? || booking.folio_account_reference.present? || folio_number.blank?

    booking.assign_folio_account_reference_from!(folio_number)
  end

  def authorize_reopen_for_correction!
    @reopen_for_correction_authorized = true
  end

  def clear_reopen_for_correction_authorization!
    @reopen_for_correction_authorized = false
  end

  private :authorize_reopen_for_correction!, :clear_reopen_for_correction_authorization!
end
