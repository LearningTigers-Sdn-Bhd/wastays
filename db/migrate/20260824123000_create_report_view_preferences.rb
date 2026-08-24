# frozen_string_literal: true

class CreateReportViewPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :report_view_preferences do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :report_key, null: false
      t.jsonb :visible_columns, null: false, default: []

      t.timestamps
    end

    add_index :report_view_preferences, %i[hotel_id user_id report_key], unique: true
  end
end
