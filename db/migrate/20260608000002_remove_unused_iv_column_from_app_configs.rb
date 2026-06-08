class RemoveUnusedIvColumnFromAppConfigs < ActiveRecord::Migration[8.0]
  def change
    remove_column :app_configs, :encrypted_value_iv, :text
  end
end
