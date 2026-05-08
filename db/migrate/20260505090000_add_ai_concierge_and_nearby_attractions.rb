class AddAiConciergeAndNearbyAttractions < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :ai_concierge_tone, :string, default: "basic", null: false
    add_column :hotels, :faq, :text
    add_column :hotels, :policy, :text

    add_column :room_types, :faq, :text

    create_table :nearby_attractions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :address
      t.string :city, null: false
      t.string :country, null: false

      t.timestamps
    end
  end
end
