# frozen_string_literal: true

# One reservation from an uploaded eZee export, resolved against the property.
#
# The rows are written once, when the file is uploaded, rather than re-derived
# on every page view. That is what lets the preview page, filter and revisit
# without re-reading the spreadsheet, and it is what the commit reads from --
# so the bookings created are the ones the operator actually approved.
class ReservationImportRow < ApplicationRecord
  # Before the commit runs:
  #   importable -- will be created
  #   imported   -- already in wastays, matched on external_reference
  #   past       -- arrival is before the business date
  #   blocked    -- cannot be created; `issues` says why
  # After it runs, an importable row becomes created or failed.
  STATUSES = %w[importable imported past blocked created failed].freeze
  ATTENTION_STATUSES = %w[blocked failed].freeze

  belongs_to :reservation_import
  belongs_to :room_type, optional: true
  belongs_to :room, optional: true
  belongs_to :booking, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :in_sheet_order, -> { order(:sheet_row) }
  scope :importable, -> { where(status: "importable") }
  # `where.not(issues: [])` would compile to NOT IN (), which is true for every
  # row -- jsonb has to be asked about its length instead.
  scope :with_issues, -> { where("jsonb_array_length(issues) > 0") }
  # Anything the operator should look at before committing: a row that cannot
  # be created, or one that will be created with a caveat.
  scope :needing_attention, -> { where(status: ATTENTION_STATUSES).or(with_issues) }

  def issue_for(field)
    issues.find { |issue| issue["field"] == field.to_s }
  end

  def errors_for_display = issues.select { |issue| issue["level"] == "error" }
  def warnings_for_display = issues.select { |issue| issue["level"] == "warning" }

  def blocked? = status == "blocked"
  def attention? = status.in?(ATTENTION_STATUSES) || issues.any?
end
