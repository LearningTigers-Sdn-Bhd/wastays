# frozen_string_literal: true

class AddDescriptionToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :description, :text
  end
end
