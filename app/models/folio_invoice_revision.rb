# frozen_string_literal: true

class FolioInvoiceRevision < ApplicationRecord
  belongs_to :hotel
  belongs_to :folio_invoice, inverse_of: :revisions
  belongs_to :issued_by, class_name: "User", optional: true

  validates :revision_number, numericality: { only_integer: true, greater_than: 0 }
  validates :revision_number, uniqueness: { scope: :folio_invoice_id }
  validates :document_reference, :issued_at, presence: true
  validates :document_reference, uniqueness: { scope: :hotel_id }
  validates :snapshot, exclusion: { in: [ nil ] }
  validate :hotel_matches_invoice

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def hotel_matches_invoice
    return if hotel.blank? || folio_invoice.blank? || folio_invoice.hotel_id == hotel_id

    errors.add(:hotel, "must match the folio invoice hotel")
  end

  def prevent_update
    errors.add(:base, "Folio invoice revisions are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "Folio invoice revisions are immutable and cannot be deleted.")
    throw :abort
  end
end
