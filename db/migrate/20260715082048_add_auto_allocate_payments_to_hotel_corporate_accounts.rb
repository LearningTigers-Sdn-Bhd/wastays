class AddAutoAllocatePaymentsToHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :hotel_corporate_accounts, :auto_allocate_payments, :boolean, default: false, null: false
  end
end
