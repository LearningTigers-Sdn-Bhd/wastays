# frozen_string_literal: true

class AddCreatedByUserToHotels < ActiveRecord::Migration[8.0]
  def change
    add_reference :hotels, :created_by_user, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
