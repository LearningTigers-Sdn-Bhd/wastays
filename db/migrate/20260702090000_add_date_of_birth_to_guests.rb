# frozen_string_literal: true

class AddDateOfBirthToGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :date_of_birth, :date
  end
end
