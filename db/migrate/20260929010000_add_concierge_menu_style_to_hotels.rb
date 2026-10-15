# frozen_string_literal: true

class AddConciergeMenuStyleToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :concierge_menu_style, :string, default: "interactive", null: false
  end
end
