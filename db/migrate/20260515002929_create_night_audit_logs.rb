class CreateNightAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :night_audit_logs do |t|
      t.references :night_audit, null: false, foreign_key: true
      t.references :hotel, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :action_type, null: false
      t.text :message
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :night_audit_logs, :action_type
  end
end
