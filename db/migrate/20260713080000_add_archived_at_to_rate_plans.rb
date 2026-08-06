# frozen_string_literal: true

class AddArchivedAtToRatePlans < ActiveRecord::Migration[8.0]
  def change
    add_column :rate_plans, :archived_at, :datetime
    add_index :rate_plans, :archived_at
  end
end
