# frozen_string_literal: true

# Gives every hotel an immutable, meaningless 5-character public identifier.
#
# Until now hotels were addressed in URLs by a name-derived FriendlyId slug, with a
# numeric-id fallback still live in the lookup paths. That made ids enumerable, broke
# every bookmark and printed concierge QR code whenever a property was renamed, and
# left support with nothing stable to quote a hotel by. `unique_id` fixes all three.
#
# The charset is the ambiguity-free one already used for booking confirmation tokens
# (A-Z + 2-9 minus I, O and L) so a code survives being read aloud or copied off a
# printout. Five characters over 31 symbols is ~28.6M combinations.
#
# Backfill runs before the unique index so the index cannot fail on a duplicate.
class AddUniqueIdToHotels < ActiveRecord::Migration[8.1]
  # Inlined rather than read off Hotel/DocumentIdentifiers: a migration has to keep
  # running years from now, whatever those constants have become since.
  CHARSET = (("A".."Z").to_a + ("2".."9").to_a - %w[I O L]).freeze
  LENGTH = 5

  def up
    add_column :hotels, :unique_id, :string

    backfill

    add_index :hotels, :unique_id, unique: true
    change_column_null :hotels, :unique_id, false
  end

  def down
    remove_column :hotels, :unique_id
  end

  private

  # Deliberately raw SQL rather than the model: the model's own validations and
  # callbacks are irrelevant here, and a half-configured hotel row must not block
  # its own backfill.
  def backfill
    taken = select_values("SELECT unique_id FROM hotels WHERE unique_id IS NOT NULL").to_set

    select_values("SELECT id FROM hotels WHERE unique_id IS NULL ORDER BY id").each do |id|
      code = nil
      code = Array.new(LENGTH) { CHARSET.sample }.join while code.nil? || taken.include?(code)
      taken << code

      execute("UPDATE hotels SET unique_id = #{connection.quote(code)} WHERE id = #{connection.quote(id)}")
    end

    say "hotels.unique_id: backfilled #{taken.size} row(s)"
  end
end
