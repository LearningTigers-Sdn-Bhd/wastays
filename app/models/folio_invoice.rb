# frozen_string_literal: true

class FolioInvoice < ApplicationRecord
  STATES = %w[finalized under_correction voided].freeze
  MUTABLE_FIELDS = %w[state current_revision_number updated_at].freeze

  belongs_to :hotel
  belongs_to :booking_folio
  belongs_to :invoice, optional: true
  belongs_to :issued_by, class_name: "User", optional: true
  has_many :revisions, -> { order(:revision_number) },
    class_name: "FolioInvoiceRevision",
    dependent: :restrict_with_error,
    inverse_of: :folio_invoice

  enum :state, STATES.index_by(&:itself), validate: true

  validates :invoice_number, :invoice_year, :invoice_reference, :issued_at, presence: true
  validates :invoice_number, uniqueness: { scope: [ :hotel_id, :invoice_year ] }
  validates :invoice_reference, uniqueness: { scope: :hotel_id }
  validates :booking_folio_id, uniqueness: true
  validates :current_revision_number, numericality: { only_integer: true, greater_than: 0 }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :folio_matches_hotel
  validate :identifier_matches_folio
  validate :folio_has_no_ar_invoice
  validate :current_revision_exists, on: :update

  before_update :prevent_immutable_changes

  delegate :booking, to: :booking_folio

  def current_revision
    revisions.find_by(revision_number: current_revision_number)
  end

  def current_document_reference
    current_revision&.document_reference || invoice_reference
  end

  private

  def folio_matches_hotel
    return if hotel.blank? || booking_folio.blank? || booking_folio.hotel_id == hotel_id

    errors.add(:booking_folio, "must belong to the invoice hotel")
  end

  def identifier_matches_folio
    return if booking_folio.blank?
    return if booking_folio.invoice_number == invoice_number &&
      booking_folio.invoice_year == invoice_year &&
      booking_folio.invoice_reference == invoice_reference

    errors.add(:base, "Folio invoice identifier must match the booking folio identifier.")
  end

  def folio_has_no_ar_invoice
    return if booking_folio_id.blank? || !ArInvoice.exists?(booking_folio_id:)

    errors.add(:booking_folio, "cannot have both a folio invoice and an AR invoice")
  end

  def current_revision_exists
    return if revisions.exists?(revision_number: current_revision_number)

    errors.add(:current_revision_number, "must reference an issued revision")
  end

  def prevent_immutable_changes
    immutable_changes = changes.keys - MUTABLE_FIELDS
    return if immutable_changes.empty?

    errors.add(:base, "Folio invoice identifiers are immutable after creation.")
    throw :abort
  end
end
