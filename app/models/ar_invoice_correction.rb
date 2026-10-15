# frozen_string_literal: true

class ArInvoiceCorrection < ApplicationRecord
  STATUSES = %w[editing processing failed completed unchanged].freeze
  belongs_to :hotel
  belongs_to :booking_folio
  belongs_to :original_receivable, class_name: "ArInvoice"
  belongs_to :replacement_receivable, class_name: "ArInvoice", optional: true
  belongs_to :opened_by, class_name: "User"
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :e_invoice_submissions, dependent: :restrict_with_error

  enum :status, STATUSES.index_by(&:itself), validate: true
  validates :reason, presence: true
  validates :original_snapshot, :corrected_snapshot, :metadata, exclusion: { in: [ nil ] }
  scope :unresolved, -> { where(status: %w[editing processing failed]) }

  validate :receivables_match_folio
  validate :preserve_original_identity, on: :update

  after_update_commit :enqueue_processing, if: -> { saved_change_to_status? && processing? }

  private

  def receivables_match_folio
    [ original_receivable, replacement_receivable ].compact.each do |receivable|
      unless receivable.hotel_id == hotel_id && receivable.booking_folio_id == booking_folio_id
        errors.add(:base, "Correction receivables must belong to the same hotel and folio")
      end
    end
  end

  def preserve_original_identity
    %w[hotel_id booking_folio_id original_receivable_id opened_by_id reason original_snapshot].each do |field|
      errors.add(field, "is immutable") if will_save_change_to_attribute?(field)
    end
    if status_in_database != "editing"
      %w[replacement_receivable_id credit_reference corrected_snapshot closed_by_id completed_at].each do |field|
        errors.add(field, "is immutable after posting") if will_save_change_to_attribute?(field)
      end
    end
  end

  def enqueue_processing
    ArInvoices::ProcessCorrectionJob.perform_later(id)
  rescue StandardError => e
    # Financial posting already committed. Keep it successful and expose a
    # retryable delivery failure rather than inviting staff to post it again.
    update!(status: "failed", error_message: "Correction saved, but document processing could not be queued: #{e.message}")
  end
end
