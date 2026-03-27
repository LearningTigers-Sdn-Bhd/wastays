class AddEditHistoryToBookingNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_notes, :edit_history, :jsonb, default: [], null: false
  end
end
