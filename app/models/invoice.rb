# frozen_string_literal: true

class Invoice < ApplicationRecord
  KINDS = %w[settled direct_bill].freeze
  STATES = %w[finalized under_correction voided].freeze
  MUTABLE_FIELDS = %w[state current_revision_number updated_at].freeze

  belongs_to :hotel
  belongs_to :booking_folio
  belongs_to :issued_by, class_name: "User", optional: true
  has_many :revisions, -> { order(:revision_number) },
    class_name: "InvoiceRevision",
    dependent: :restrict_with_error,
    inverse_of: :invoice
  has_one :receivable, dependent: :restrict_with_error, inverse_of: :invoice

  enum :kind, KINDS.index_by(&:itself), prefix: true, validate: true
  enum :state, STATES.index_by(&:itself), validate: true

  validates :invoice_number, :invoice_year, :invoice_reference, :issued_on, :issued_at, presence: true
  validates :invoice_number, uniqueness: { scope: [ :hotel_id, :kind, :invoice_year ] }
  validates :invoice_reference, uniqueness: { scope: :hotel_id }
  validates :booking_folio_id, uniqueness: true
  validates :current_revision_number, numericality: { only_integer: true, greater_than: 0 }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :folio_matches_hotel
  validate :current_revision_exists, on: :update

  before_update :prevent_immutable_changes

  delegate :booking, to: :booking_folio

  def current_revision
    revisions.find_by(revision_number: current_revision_number)
  end

  def current_document_reference
    current_revision&.document_reference || invoice_reference
  end

  def formatted_invoice_number
    invoice_reference
  end

  private

  def folio_matches_hotel
    return if hotel.blank? || booking_folio.blank? || booking_folio.hotel_id == hotel_id

    errors.add(:booking_folio, "must belong to the invoice hotel")
  end

  def current_revision_exists
    return if revisions.exists?(revision_number: current_revision_number)

    errors.add(:current_revision_number, "must reference an issued revision")
  end

  def prevent_immutable_changes
    immutable_changes = changes.keys - MUTABLE_FIELDS
    return if immutable_changes.empty?

    errors.add(:base, "Invoice identity is immutable after creation.")
    throw :abort
  end
end
