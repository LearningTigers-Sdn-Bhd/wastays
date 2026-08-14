# frozen_string_literal: true

# Reissues every hotel code as a plain number, in creation order, starting at 10101.
#
# The codes were random 5-character tokens, chosen so they could not be enumerated.
# Hotels asked for numbers instead: they are quoted down a phone line, typed into a
# support ticket and sorted in a spreadsheet, and a random token is bad at all three.
# The cost is accepted knowingly — sequential codes disclose how many properties exist,
# though not their data, since authorization still decides who may open one.
#
# Old letter codes stop resolving. Links built on the legacy `slug` keep working, as
# they always have, because `Hotel.locate` still falls back to it.
class RenumberHotelUniqueIds < ActiveRecord::Migration[8.1]
  FLOOR = 10_101

  # One statement, so the unique index never sees an intermediate duplicate: every new
  # value is numeric and every old one is alphabetic, so the two sets cannot overlap.
  #
  # Raw SQL rather than the model, matching the original backfill — `unique_id` is
  # immutable to Active Record by design, and a half-configured hotel row must not be
  # able to block its own renumber with an unrelated validation.
  def up
    execute(<<~SQL.squish)
      UPDATE hotels SET unique_id = sub.code
      FROM (
        SELECT id, (#{FLOOR - 1} + ROW_NUMBER() OVER (ORDER BY created_at, id))::text AS code
        FROM hotels
      ) sub
      WHERE hotels.id = sub.id
    SQL

    say "hotels.unique_id: renumbered #{select_value('SELECT COUNT(*) FROM hotels')} row(s) from #{FLOOR}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "the random codes replaced here were not recorded anywhere"
  end
end
