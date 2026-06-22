# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking
  has_many :folio_transactions, dependent: :restrict_with_error
  has_many :folio_forecasted_charges, dependent: :destroy
  has_many :deposits, dependent: :restrict_with_error
  has_many :financial_audit_events, dependent: :restrict_with_error

  enum :status, { open: "open", closed: "closed" }, validate: true

  validates :folio_number, presence: true, uniqueness: { scope: :hotel_id }
  validates :status, presence: true
  validates :invoice_number, uniqueness: { scope: :hotel_id, allow_nil: true }
  validate :hotel_matches_booking
  validate :closed_folio_reopen_must_be_authorized
  before_destroy :guard_night_audit_operational_change

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

  def authorize_reopen_for_correction!
    @reopen_for_correction_authorized = true
  end

  def clear_reopen_for_correction_authorization!
    @reopen_for_correction_authorized = false
  end

  private :authorize_reopen_for_correction!, :clear_reopen_for_correction_authorization!
end
