# frozen_string_literal: true

class NightAuditLog < ApplicationRecord
  belongs_to :night_audit
  belongs_to :hotel
  belongs_to :user, optional: true

  validates :action_type, presence: true

  # Define common action types as constants or an enum if preferred
  ACTION_TYPES = %w[
    process_started
    check_due_outs
    check_missing_timestamps
    check_open_requests
    blocker_found
    exception_found
    item_skipped
    item_failed
    blocker_resolved
    completed
    failed
  ].freeze

  validates :action_type, inclusion: { in: ACTION_TYPES }
end
