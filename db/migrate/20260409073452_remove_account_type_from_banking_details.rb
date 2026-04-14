class RemoveAccountTypeFromBankingDetails < ActiveRecord::Migration[8.0]
  def change
    remove_column :banking_details, :account_type, :string
  end
end
