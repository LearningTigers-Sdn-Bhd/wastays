class AddBlockedDetailsToNightAudits < ActiveRecord::Migration[8.0]
  def change
    add_column :night_audits, :blocked_details, :jsonb, null: false, default: {}
  end
end
