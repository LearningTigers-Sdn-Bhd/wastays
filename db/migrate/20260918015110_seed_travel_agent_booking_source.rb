# frozen_string_literal: true

# The registry is seeded once, by the migration that created the table, so a
# new entry in BookingSource::DEFAULT_SOURCES does not reach a database that has
# already run it. Re-seeding is idempotent -- it upserts each default by key --
# so this brings "travel_agent" to existing environments without touching the
# sources a hotel has edited or added of its own.
class SeedTravelAgentBookingSource < ActiveRecord::Migration[8.1]
  def up
    BookingSource.seed_defaults!
    BookingSource.reset_registry_cache!
  end

  def down
    BookingSource.find_by(key: "travel_agent")&.destroy
    BookingSource.reset_registry_cache!
  end
end
