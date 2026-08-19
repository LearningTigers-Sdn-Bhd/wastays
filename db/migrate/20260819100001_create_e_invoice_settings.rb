# frozen_string_literal: true

class CreateEInvoiceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :e_invoice_settings do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.boolean :intermediary_enabled, null: false, default: false

      t.string :hotel_tin
      t.string :hotel_brn
      t.string :supplier_msic_code
      t.string :supplier_business_description
      t.string :supplier_sst_registration_number
      t.string :supplier_address_line1
      t.string :supplier_address_line2
      t.string :supplier_city
      t.string :supplier_postal_code
      t.string :supplier_state_code
      t.string :supplier_country_code
      t.string :supplier_contact_phone
      t.string :supplier_contact_email

      t.timestamps
    end
  end
end
