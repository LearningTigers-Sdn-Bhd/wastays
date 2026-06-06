# frozen_string_literal: true

namespace :hotel_knowledges do
  desc "Prune hotel knowledge diagnostics older than RETENTION_DAYS days (default: 90)"
  task prune_diagnostics: :environment do
    retention_days = ENV.fetch("RETENTION_DAYS", "90").to_i
    cutoff = retention_days.days.ago
    deleted = HotelKnowledgeDiagnostic.where(created_at: ...cutoff).delete_all

    puts "Deleted #{deleted} hotel knowledge diagnostics older than #{retention_days} days."
  end
end
