class AddIdentityFieldsToGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :gender, :string
    add_column :guests, :country, :string
    add_column :guests, :document_type, :string
  end
end
