# frozen_string_literal: true

class LegacyBookingSplitLineage < ApplicationRecord
  REVIEW_STATUSES = %w[pending approved rejected].freeze

  belongs_to :legacy_booking, class_name: "Booking"
  belongs_to :group_booking
  belongs_to :child_booking, class_name: "Booking"
  belongs_to :booking_room

  validates :batch_id, :review_status, presence: true
  validates :review_status, inclusion: { in: REVIEW_STATUSES }
  validates :child_booking_id, :booking_room_id, uniqueness: true
  validates :legacy_booking_id, uniqueness: { conditions: -> { where(anchor: true) } }, if: :anchor?
  validate :lineage_is_consistent

  validate :review_transition_is_allowed, on: :update
  before_update :prevent_lineage_mutation
  before_destroy :prevent_mutation

  private

  def lineage_is_consistent
    return if legacy_booking.blank? || group_booking.blank? || child_booking.blank? || booking_room.blank?

    errors.add(:child_booking, "must belong to the lineage group") unless child_booking.group_booking_id == group_booking_id
    errors.add(:booking_room, "must belong to the child booking") unless booking_room.booking_id == child_booking_id
    errors.add(:anchor, "must map the legacy booking") if anchor? && child_booking_id != legacy_booking_id
  end

  def review_transition_is_allowed
    if will_save_change_to_review_reason? && !will_save_change_to_review_status?
      errors.add(:review_reason, "can only change with a review status transition")
    end
    return unless will_save_change_to_review_status?
    return if review_status_was == "pending" && review_status.in?(%w[approved rejected])

    errors.add(:review_status, "can only transition from pending to approved or rejected")
  end

  def prevent_lineage_mutation
    immutable_changes = changes_to_save.keys - %w[review_status review_reason updated_at]
    return if immutable_changes.empty?

    prevent_mutation
  end

  def prevent_mutation
    errors.add(:base, "Legacy booking split lineage is immutable.")
    throw :abort
  end
end
