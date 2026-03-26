class CreatePreCheckins < ActiveRecord::Migration[8.0]
  def change
    create_table :pre_checkins do |t|
      t.references :booking, null: false, foreign_key: true
      t.string :status
      t.string :token
      t.datetime :completed_at
      t.string :document_status
      t.string :signature_status
      t.jsonb :metadata

      t.timestamps
    end
  end
end
