class CreateChannelMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :channel_mappings do |t|
      t.references :mappable, polymorphic: true, null: false
      t.string :provider, null: false
      t.string :external_id, null: false

      t.timestamps
    end

    add_index :channel_mappings, [ :provider, :external_id ], unique: true
    add_index :channel_mappings, [ :provider, :mappable_type, :mappable_id ], unique: true, name: "idx_channel_mappings_provider_mappable"
  end
end
