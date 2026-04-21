class ChangeTrainerToNameInOnboardingSessions < ActiveRecord::Migration[8.0]
  def change
    remove_reference :onboarding_sessions, :trainer, foreign_key: { to_table: :users }, index: true
    add_column :onboarding_sessions, :trainer_name, :string, null: false, default: ""
  end
end
