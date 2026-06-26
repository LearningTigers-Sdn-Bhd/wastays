# frozen_string_literal: true

class CreateFolioRoutingRules < ActiveRecord::Migration[8.0]
  def change
    create_table :folio_routing_rules do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true
      t.references :target_folio, null: false, foreign_key: { to_table: :booking_folios }
      t.boolean :active, null: false, default: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :folio_routing_rules,
      [ :booking_id, :transaction_code_id ],
      unique: true,
      where: "active",
      name: "idx_folio_routing_rules_one_active_per_code"
  end
end
