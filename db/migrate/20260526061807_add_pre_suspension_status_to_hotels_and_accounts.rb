class AddPreSuspensionStatusToHotelsAndAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :pre_suspension_status, :string
    add_column :accounts, :pre_suspension_status, :string
  end
end
