class DropOnboardingTasks < ActiveRecord::Migration[8.0]
  def change
    drop_table :onboarding_tasks do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :task_name, null: false
      t.string :status, default: "pending", null: false
      t.datetime :completed_at
      t.timestamps
    end
  end
end
