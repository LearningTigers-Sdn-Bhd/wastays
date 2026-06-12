class AddDiscardedAtToGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :discarded_at, :datetime
    add_index :guests, :discarded_at
  end
end
