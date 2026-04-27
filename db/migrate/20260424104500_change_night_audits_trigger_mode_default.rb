class ChangeNightAuditsTriggerModeDefault < ActiveRecord::Migration[8.0]
  def change
    change_column_default :night_audits, :trigger_mode, from: "manual_now", to: "manual"
  end
end
