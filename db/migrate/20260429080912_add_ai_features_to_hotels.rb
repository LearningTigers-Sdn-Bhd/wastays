class AddAiFeaturesToHotels < ActiveRecord::Migration[7.2]
  def change
    add_column :hotels, :ai_provider_enabled, :boolean, default: false
    add_column :hotels, :ai_provider_name, :string
    add_column :hotels, :ai_provider_key, :text
  end
end

