class CreateOnboardingTables < ActiveRecord::Migration[8.0]
  def change
    create_table :onboarding_tasks do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :task_name, null: false
      t.string :status, default: "pending", null: false
      t.datetime :completed_at
      t.timestamps
    end

    create_table :onboarding_sessions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :trainer, null: false, foreign_key: { to_table: :users }
      t.string :meeting_link
      t.datetime :scheduled_at
      t.datetime :completed_at
      t.string :status, default: "scheduled", null: false
      t.text :notes
      t.timestamps
    end

    add_index :onboarding_tasks, [:hotel_id, :task_name], unique: true
  end
end
