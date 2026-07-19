# frozen_string_literal: true

class AddPriorityNoteToRoomStatuses < ActiveRecord::Migration[8.0]
  def change
    add_column :room_statuses, :priority_note, :text
  end
end
