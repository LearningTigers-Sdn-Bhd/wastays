# frozen_string_literal: true

class FolioRoutingRule < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking
  belongs_to :transaction_code
  belongs_to :target_folio, class_name: "BookingFolio"
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true


  scope :active, -> { where(active: true) }

  validates :hotel, :booking, :transaction_code, :target_folio, presence: true
  validates :transaction_code_id, uniqueness: {
    scope: :booking_id,
    conditions: -> { where(active: true) },
    message: "already has an active routing rule for this booking"
  }, if: :active?
  validate :booking_belongs_to_hotel
  validate :target_folio_belongs_to_booking
  validate :target_folio_belongs_to_hotel
  validate :transaction_code_belongs_to_hotel
  validate :effective_dates_are_ordered


  def effective_on?(date)
    date = date.to_date
    (effective_from.blank? || effective_from <= date) && (effective_until.blank? || effective_until >= date)
  end

  private

  def booking_belongs_to_hotel
    return if booking.blank? || hotel_id.blank? || booking.hotel_id == hotel_id

    errors.add(:booking, "must belong to the same hotel")
  end

  def target_folio_belongs_to_booking
    return if target_folio.blank? || booking_id.blank? || target_folio.booking_id == booking_id

    errors.add(:target_folio, "must belong to the same booking")
  end

  def target_folio_belongs_to_hotel
    return if target_folio.blank? || hotel_id.blank? || target_folio.hotel_id == hotel_id

    errors.add(:target_folio, "must belong to the same hotel")
  end

  def transaction_code_belongs_to_hotel
    return if transaction_code.blank? || hotel_id.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def effective_dates_are_ordered
    return if effective_from.blank? || effective_until.blank? || effective_until >= effective_from

    errors.add(:effective_until, "must be on or after effective from")
  end

end
