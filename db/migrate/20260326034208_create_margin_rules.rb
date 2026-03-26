class CreateMarginRules < ActiveRecord::Migration[8.0]
  def change
    create_table :margin_rules do |t|
      t.references :settable, polymorphic: true, null: false
      t.decimal :rate
      t.string :status

      t.timestamps
    end
  end
end
