# frozen_string_literal: true

module Logs
  class PruneOldEntriesJob < ApplicationJob
    queue_as :default

    def perform
      deleted = PruneOldEntries.call
      Rails.logger.info "[Logs] Pruned #{deleted[:mail_events]} mail events and #{deleted[:error_events]} error events."
    end
  end
end
