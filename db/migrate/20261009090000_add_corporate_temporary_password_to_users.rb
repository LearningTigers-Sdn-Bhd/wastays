class AddCorporateTemporaryPasswordToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :temporary_password, :text
    add_reference :users, :temporary_password_hotel, foreign_key: { to_table: :hotels }
  end
end
