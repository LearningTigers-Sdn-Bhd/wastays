# frozen_string_literal: true

# Nationality had no toggle, so every card showed it. Now that it is a toggle,
# add it to the lists that hotels already saved and to the snapshots on cards
# that guests already signed. Without this, nationality would disappear from
# cards that show it today.
class BackfillNationalityRegistrationCardField < ActiveRecord::Migration[8.0]
  def up
    append_field("hotels", "guest_registration_card_fields")
    append_field("guest_registration_cards", "display_fields_snapshot")
  end

  def down
    remove_field("hotels", "guest_registration_card_fields")
    remove_field("guest_registration_cards", "display_fields_snapshot")
  end

  private

  def append_field(table, column)
    execute <<~SQL.squish
      UPDATE #{table}
      SET #{column} = #{column} || '["nationality"]'::jsonb
      WHERE #{column} IS NOT NULL
        AND NOT (#{column} @> '["nationality"]')
    SQL
  end

  def remove_field(table, column)
    execute <<~SQL.squish
      UPDATE #{table}
      SET #{column} = #{column} - 'nationality'
      WHERE #{column} IS NOT NULL
    SQL
  end
end
