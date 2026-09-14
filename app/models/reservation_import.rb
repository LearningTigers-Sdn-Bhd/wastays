# frozen_string_literal: true

# One run of the eZee reservation importer.
#
# It exists so the import can run in the background and still be watched: a
# property's whole forward book is well over a thousand reservations, each one
# building a financial snapshot and a folio, which is far too much for a
# request. The row keeps the counts durable, so a reload shows real progress
# rather than a spinner that has lost its place.
class ReservationImport < ApplicationRecord
  STATUSES = %w[draft queued running completed failed].freeze
  # Broadcasting every row would be a thousand messages for one import. The
  # screen only needs to look alive, so updates are throttled to whole percents
  # with a floor for small files.
  BROADCAST_EVERY = 5

  belongs_to :hotel
  belongs_to :user, optional: true
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def running? = status.in?(%w[queued running])
  def finished? = status.in?(%w[completed failed])

  def percent_complete
    return 0 if total_rows.zero?
    return 100 if finished?

    [ (processed_rows * 100.0 / total_rows).floor, 100 ].min
  end

  def duration
    return nil if started_at.blank?

    ((finished_at || Time.current) - started_at).round
  end

  def record_failure!(reference, message)
    self.failures = failures + [ { "reference" => reference, "message" => message } ]
    self.failed_count = failures.size
  end

  # Called from the job as it works. Writes every time so a reload is accurate,
  # but only broadcasts on a visible change, so the socket is not flooded.
  def advance!(step: nil, processed: nil, created: nil, groups: nil)
    previous_percent = percent_complete
    self.step = step if step
    self.processed_rows = processed if processed
    self.created_count = created if created
    self.group_count = groups if groups
    save!

    changed_step = saved_change_to_step?
    crossed = percent_complete != previous_percent && (processed_rows % BROADCAST_EVERY).zero?
    broadcast_progress if changed_step || crossed
  end

  def broadcast_progress
    broadcast_replace_to(
      self,
      target: "reservation_import_progress",
      partial: "admin/hotels/reservation_imports/progress",
      locals: { import: self }
    )
  rescue StandardError => e
    # A broadcast that cannot be delivered must never fail the import behind it.
    Rails.logger.warn("Reservation import #{id} could not broadcast: #{e.message}")
  end
end
