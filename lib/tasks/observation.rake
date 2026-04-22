namespace :observation do
  desc "Prune observation entries older than 24 hours"
  task prune: :environment do
    count = ObservationEntry.where("created_at < ?", 24.hours.ago).delete_all
    puts "Pruned #{count} observation entries."
  end
end
