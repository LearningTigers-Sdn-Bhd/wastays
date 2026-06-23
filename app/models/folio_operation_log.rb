# frozen_string_literal: true

class FolioOperationLog < ApplicationRecord
  OPERATION_TYPES = %w[
    create_folio
    rename_folio
    set_default_folio
    move_transaction
    split_transaction
    move_forecast
    close_folio
    reopen_folio
    void_folio
    correction
  ].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :source_folio, class_name: "BookingFolio", optional: true
  belongs_to :target_folio, class_name: "BookingFolio", optional: true
  belongs_to :source_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :target_transaction, class_name: "FolioTransaction", optional: true

  validates :operation_type, presence: true, inclusion: { in: OPERATION_TYPES }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :hotel_matches_booking
  validate :folio_context_matches_booking
  validate :transaction_context_matches_booking

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def hotel_matches_booking
    return if booking.blank? || hotel_id.blank? || booking.hotel_id == hotel_id

    errors.add(:hotel, "must match booking hotel")
  end

  def folio_context_matches_booking
    [ source_folio, target_folio ].compact.each do |folio|
      next if folio.booking_id == booking_id && folio.hotel_id == hotel_id

      errors.add(:base, "Folio context must match operation booking and hotel.")
    end
  end

  def transaction_context_matches_booking
    [ source_transaction, target_transaction ].compact.each do |transaction|
      folio = transaction.booking_folio
      next if folio.booking_id == booking_id && folio.hotel_id == hotel_id

      errors.add(:base, "Transaction context must match operation booking and hotel.")
    end
  end

  def prevent_update
    errors.add(:base, "Folio operation logs are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "Folio operation logs are immutable and cannot be deleted.")
    throw :abort
  end
end
