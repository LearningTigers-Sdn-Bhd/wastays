class AddEncryptionIvToAppConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :app_configs, :encrypted_value_iv, :text
  end
end
