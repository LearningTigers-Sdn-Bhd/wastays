# frozen_string_literal: true

module Logs
  # Deletes old rows of the admin Mail Log and the Activity Log error tab.
  # The audit tables are not pruned. They are the record of what staff did.
  class PruneOldEntries
    MAIL_RETENTION = 90.days
    ERROR_RETENTION = 30.days
    BATCH_SIZE = 5_000

    def self.call(now: Time.current, batch_size: BATCH_SIZE)
      {
        mail_events: prune(MailEvent.where(sent_at: ...(now - MAIL_RETENTION)), batch_size),
        error_events: prune(ErrorEvent.where(occurred_at: ...(now - ERROR_RETENTION)), batch_size)
      }
    end

    def self.prune(scope, batch_size)
      scope.in_batches(of: batch_size).delete_all
    end
    private_class_method :prune
  end
end
