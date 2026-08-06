# frozen_string_literal: true

module ObservationDeck
  class PruneEntries
    RETENTION_PERIOD = 7.days
    BATCH_SIZE = 10_000

    def self.call(cutoff: RETENTION_PERIOD.ago, batch_size: BATCH_SIZE)
      ObservationEntry
        .where("created_at < ?", cutoff)
        .in_batches(of: batch_size)
        .delete_all
    end
  end
end
