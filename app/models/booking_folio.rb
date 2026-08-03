# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  FOLIO_TYPES = %w[guest external house].freeze
  PAYER_TYPES = %w[guest company agent hotel custom].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :booking_room, optional: true
  belongs_to :booking_billing_party, optional: true
  belongs_to :hotel_corporate_account, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :folio_transactions, dependent: :restrict_with_error
  has_many :folio_forecasted_charges, dependent: :destroy
  has_one :ar_invoice, dependent: :restrict_with_error
  has_one :invoice, dependent: :restrict_with_error
  has_one :receivable, class_name: "Receivable", dependent: :restrict_with_error
  has_many :receipts, through: :folio_transactions
  has_many :target_folio_routing_rules, class_name: "FolioRoutingRule", foreign_key: :target_folio_id, dependent: :restrict_with_error
  has_many :deposit_movements, dependent: :restrict_with_error
  has_many :financial_audit_events, dependent: :restrict_with_error
  has_many :source_operation_logs, class_name: "FolioOperationLog", foreign_key: :source_folio_id, dependent: :restrict_with_error
  has_many :target_operation_logs, class_name: "FolioOperationLog", foreign_key: :target_folio_id, dependent: :restrict_with_error

  enum :status, { open: "open", closed: "closed", voided: "voided" }, validate: true
  enum :folio_type, FOLIO_TYPES.index_by(&:itself), prefix: true, validate: true
  enum :payer_type, PAYER_TYPES.index_by(&:itself), prefix: true, validate: true

  validates :folio_number, presence: true, uniqueness: { scope: [ :hotel_id, :folio_year ] }
  validates :currency, presence: true
  validates :opened_at, presence: true
  validates :status, presence: true
  validates :invoice_number, uniqueness: { scope: [ :hotel_id, :invoice_year ], allow_nil: true }
  validates :folio_sequence, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :folio_sequence, uniqueness: { scope: :booking_id, allow_nil: true }
  validates :is_primary, uniqueness: { scope: [ :booking_id, :booking_room_id ], conditions: -> { where(is_primary: true) }, if: :is_primary? }
  validate :hotel_matches_booking
  validate :booking_room_matches_booking
  validate :booking_billing_party_matches_booking
  validate :booking_billing_party_matches_payer
  validate :company_payer_requires_active_hotel_corporate_account
  validate :closed_folio_reopen_must_be_authorized
  validate :last_primary_folio_cannot_be_unset
  validate :closed_folio_fields_are_restricted, on: :update
  before_validation :assign_defaults
  before_validation :assign_invoice_reference
  before_validation :normalize_payer_type
  before_validation :clear_hotel_corporate_account_unless_company_payer
  after_create :ensure_booking_folio_account_reference
  before_destroy :guard_night_audit_operational_change
  before_destroy :prevent_destroying_last_folio

  scope :room_scoped, -> { where.not(booking_room_id: nil) }
  scope :booking_level, -> { where(booking_room_id: nil) }

  def outstanding_balance
    total_charges - total_payments + total_adjustments
  end

  def unsettled_forecasts
    folio_forecasted_charges.forecast
  end

  def projected_forecasts
    return folio_forecasted_charges.none if status == "closed" || booking.blank?
    return folio_forecasted_charges.none if booking.status.in?(%w[cancelled completed no_show voided])

    unsettled_forecasts
      .where(
        FolioForecastedCharge.arel_table[:charge_kind].in(%w[extra_charge extra_charge_tax])
          .or(FolioForecastedCharge.arel_table[:stay_date].lt(booking.check_out.to_date))
      )
      .order(:stay_date, :charge_kind, :identity)
  end

  def all_charges_posted?
    folio_forecasted_charges.forecast.none?
  end

  def projected_outstanding_balance
    outstanding_balance + projected_forecasts.sum(:amount)
  end

  # A folio is identified by its reference; the label is an optional override
  # a human sets deliberately, and clearing it reverts to the reference.
  def display_name
    label.presence || folio_reference_display
  end

  def display_option_label
    [ label.presence, folio_reference_display ].compact_blank.join(" · ")
  end

  # For dropdowns and resolvers where a bare reference is too terse.
  def display_with_payer
    [ display_name, payer_display_label ].compact_blank.join(" · ")
  end

  def payer_display_label
    case payer_type
    when "company"
      [ "Corporate Account", hotel_corporate_account&.corporate_account&.name ].compact_blank.join(": ")
    else
      payer_type.to_s.humanize
    end
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

  # The sanctioned door through `closed_folio_reopen_must_be_authorized`.
  #
  # Reopening a closed folio is guarded because it puts an invoiced, settled
  # ledger back into an editable state. The guard is not the obstacle — it is
  # the point — so this grants the authorization for exactly one block and
  # always withdraws it, even when the block raises.
  #
  # Callers are responsible for the permission check, the lock and the
  # operation log; this only lifts the validation.
  def reopening_for_correction
    authorize_reopen_for_correction!
    yield self
  ensure
    clear_reopen_for_correction_authorization!
  end

  # Invoice allocation is part of the controlled close transaction. Closed
  # folios otherwise remain immutable through the normal update path.
  def assign_invoice_identifier_for_closure!(allocation)
    @assign_invoice_identifier_for_closure_authorized = true
    update!(
      invoice_number: allocation.number,
      invoice_year: allocation.year,
      invoice_reference: allocation.reference
    )
  ensure
    @assign_invoice_identifier_for_closure_authorized = false
  end

  private

  def guard_night_audit_operational_change
    NightAudits::OperationalChangeGuard.call!(hotel: hotel, action: :remove_folio)
  end

  def assign_defaults
    self.folio_type ||= "guest"
    self.payer_type ||= "guest"
    self.currency ||= booking&.currency.presence || hotel&.default_currency.presence || "MYR"
    self.opened_at ||= Time.current
    self.folio_year ||= DocumentIdentifiers::Issuer.sequence_year(hotel:) if hotel && folio_number.present?
    self.folio_sequence ||= next_folio_sequence if booking.present?
  end

  def assign_invoice_reference
    self.invoice_year ||= DocumentIdentifiers::Issuer.sequence_year(hotel:) if hotel && invoice_number.present?
    self.invoice_reference ||= DocumentIdentifiers::Issuer.format(hotel:, type: :invoice, year: invoice_year, number: invoice_number)
  end

  def normalize_payer_type
    case folio_type
    when "guest"
      self.payer_type = "guest"
    when "house"
      self.payer_type = "hotel"
    end
  end

  def clear_hotel_corporate_account_unless_company_payer
    self.hotel_corporate_account = nil unless payer_type == "company"
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

  def booking_room_matches_booking
    return if booking_room.blank? || booking_id.blank? || booking_room.booking_id == booking_id

    errors.add(:booking_room, "must belong to the same booking")
  end

  def booking_billing_party_matches_booking
    return if booking_billing_party.blank?

    if booking_id.present? && booking_billing_party.booking_id != booking_id
      errors.add(:booking_billing_party, "must belong to the same booking")
    end
    if hotel_id.present? && booking_billing_party.hotel_id != hotel_id
      errors.add(:booking_billing_party, "must belong to the same hotel")
    end
  end

  def booking_billing_party_matches_payer
    return if booking_billing_party.blank?

    case booking_billing_party.party_kind
    when "guest"
      errors.add(:booking_billing_party, "must match guest payer type") unless payer_type == "guest"
    when "company"
      errors.add(:booking_billing_party, "must match company payer type") unless payer_type == "company"
      if hotel_corporate_account_id.present? && hotel_corporate_account_id != booking_billing_party.hotel_corporate_account_id
        errors.add(:booking_billing_party, "must match the selected company account")
      end
    end
  end

  def company_payer_requires_active_hotel_corporate_account
    return unless payer_type == "company"

    if hotel_corporate_account.blank?
      return unless new_record? || will_save_change_to_payer_type? || will_save_change_to_hotel_corporate_account_id?

      errors.add(:hotel_corporate_account, "must be selected for Corporate Account folios")
      return
    end

    if hotel_id.present? && hotel_corporate_account.hotel_id != hotel_id
      errors.add(:hotel_corporate_account, "must belong to the folio hotel")
    end

    errors.add(:hotel_corporate_account, "must be active") unless hotel_corporate_account.active?
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
    return if primary_scope.where.not(id: id).where(is_primary: true).exists?

    errors.add(:is_primary, "must remain set until another primary folio exists in the same scope")
  end

  def primary_scope
    booking.booking_folios.where(booking_room_id: booking_room_id)
  end

  def closed_folio_fields_are_restricted
    return unless status_in_database.in?(%w[closed voided])
    return if will_save_change_to_status?
    return if @assign_invoice_identifier_for_closure_authorized

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

    booking.assign_folio_account_reference_from!(folio_number, folio_year: folio_year)
  end

  def authorize_reopen_for_correction!
    @reopen_for_correction_authorized = true
  end

  def clear_reopen_for_correction_authorization!
    @reopen_for_correction_authorized = false
  end
end
