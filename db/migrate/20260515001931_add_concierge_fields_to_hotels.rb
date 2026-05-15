class AddConciergeFieldsToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :contact_phone, :string
    add_column :hotels, :contact_email, :string
    add_column :hotels, :whatsapp_number, :string
    add_column :hotels, :concierge_enabled, :boolean, default: true, null: false
  end
end
