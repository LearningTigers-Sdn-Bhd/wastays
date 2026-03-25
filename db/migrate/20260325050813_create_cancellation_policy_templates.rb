class CreateCancellationPolicyTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :cancellation_policy_templates do |t|
      t.string :name
      t.text :body

      t.timestamps
    end
  end
end
