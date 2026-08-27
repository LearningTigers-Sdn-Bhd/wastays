# frozen_string_literal: true

# The rooms table is the whole room directory now, and room groups hold rooms
# rather than categories. Both columns are dead.
class RemoveLegacyRoomDirectoryFields < ActiveRecord::Migration[8.0]
  def up
    remove_index :room_types, :room_group_id, if_exists: true
    remove_foreign_key :room_types, :room_groups, if_exists: true
    remove_column :room_types, :room_group_id
    remove_column :room_types, :room_numbers
  end

  def down
    add_column :room_types, :room_numbers, :jsonb, default: []
    add_column :room_types, :room_group_id, :bigint
    add_index :room_types, :room_group_id
    add_foreign_key :room_types, :room_groups

    # Rebuild the list from the physical rooms, which have been the source of
    # truth since Milestone 6.
    execute(<<~SQL.squish)
      UPDATE room_types
      SET room_numbers = COALESCE(directory.numbers, '[]'::jsonb)
      FROM (
        SELECT room_type_id, jsonb_agg(number ORDER BY position, id) AS numbers
        FROM rooms
        WHERE archived_at IS NULL
        GROUP BY room_type_id
      ) AS directory
      WHERE room_types.id = directory.room_type_id
    SQL
  end
end
