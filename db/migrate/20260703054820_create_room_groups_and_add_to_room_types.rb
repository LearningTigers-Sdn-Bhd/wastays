# frozen_string_literal: true

class CreateRoomGroupsAndAddToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :room_groups do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    add_reference :room_types, :room_group, foreign_key: true
  end
end
