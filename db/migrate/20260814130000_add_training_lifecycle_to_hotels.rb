# frozen_string_literal: true

class AddTrainingLifecycleToHotels < ActiveRecord::Migration[8.1]
  def up
    add_column :hotels, :training_started_at, :datetime
    add_column :hotels, :training_data_decision, :string
    add_column :hotels, :training_completed_at, :datetime
    add_reference :hotels, :training_completed_by, foreign_key: { to_table: :users }
    add_column :hotels, :training_reset_state, :string

    execute <<~SQL.squish
      UPDATE hotels
      SET training_started_at = CURRENT_TIMESTAMP
      WHERE status = 'pending_review'
    SQL
  end

  def down
    remove_column :hotels, :training_reset_state
    remove_reference :hotels, :training_completed_by, foreign_key: { to_table: :users }
    remove_column :hotels, :training_completed_at
    remove_column :hotels, :training_data_decision
    remove_column :hotels, :training_started_at
  end
end
