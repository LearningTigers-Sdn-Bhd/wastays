class AddSalespersonIdToHotels < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:hotels, :salesperson_id)
      add_reference :hotels, :salesperson, foreign_key: { to_table: :users }, index: true
    end

    unless index_exists?(:hotels, :salesperson_id)
      add_index :hotels, :salesperson_id
    end

    unless foreign_key_exists?(:hotels, :users, column: :salesperson_id)
      add_foreign_key :hotels, :users, column: :salesperson_id
    end
  end
end
