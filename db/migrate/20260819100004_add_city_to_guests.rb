# frozen_string_literal: true

class AddCityToGuests < ActiveRecord::Migration[8.1]
  def change
    add_column :guests, :city, :string
  end
end
