namespace :observation do
  desc "Prune observation entries older than 7 days"
  task prune: :environment do
    count = ObservationDeck::PruneEntries.call
    puts "Pruned #{count} observation entries older than 7 days."
  end
end
