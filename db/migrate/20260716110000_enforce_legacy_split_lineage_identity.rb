# frozen_string_literal: true

class EnforceLegacySplitLineageIdentity < ActiveRecord::Migration[8.0]
  def change
    add_index :legacy_booking_split_lineages, :child_booking_id, unique: true,
      name: "idx_legacy_split_lineages_unique_child"
    add_index :legacy_booking_split_lineages, :booking_room_id, unique: true,
      name: "idx_legacy_split_lineages_unique_room"
    add_index :legacy_booking_split_lineages, :legacy_booking_id, unique: true,
      where: "anchor = TRUE",
      name: "idx_legacy_split_lineages_unique_anchor"
  end
end
