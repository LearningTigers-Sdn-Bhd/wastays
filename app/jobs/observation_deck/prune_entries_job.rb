# frozen_string_literal: true

module ObservationDeck
  class PruneEntriesJob < ApplicationJob
    queue_as :default

    def perform
      deleted_count = PruneEntries.call
      Rails.logger.info "[ObservationDeck] Pruned #{deleted_count} entries older than 7 days."
    end
  end
end
