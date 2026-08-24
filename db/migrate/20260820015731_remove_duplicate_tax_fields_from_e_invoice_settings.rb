class RemoveDuplicateTaxFieldsFromEInvoiceSettings < ActiveRecord::Migration[8.1]
  # hotel_tin / hotel_brn / supplier_sst_registration_number duplicated
  # hotels.tin / hotels.ssm_number / hotels.sst_registration_number, and could
  # silently diverge from them (that's exactly how this migration got written
  # - a hotel's real LHDN TIN sat in e_invoice_settings while a stale
  # placeholder sat on the hotel record). The hotel record is now the single
  # source of truth; e_invoice_settings reads through to it.
  class MigrationHotel < ApplicationRecord
    self.table_name = "hotels"
  end

  class MigrationEInvoiceSetting < ApplicationRecord
    self.table_name = "e_invoice_settings"
  end

  def up
    MigrationEInvoiceSetting.reset_column_information

    MigrationEInvoiceSetting.find_each do |setting|
      hotel = MigrationHotel.find_by(id: setting.hotel_id)
      next unless hotel

      hotel.update_columns(
        tin: setting.hotel_tin.presence || hotel.tin,
        ssm_number: setting.hotel_brn.presence || hotel.ssm_number,
        sst_registration_number: setting.supplier_sst_registration_number.presence || hotel.sst_registration_number
      )
    end

    remove_column :e_invoice_settings, :hotel_tin, :string
    remove_column :e_invoice_settings, :hotel_brn, :string
    remove_column :e_invoice_settings, :supplier_sst_registration_number, :string
  end

  def down
    add_column :e_invoice_settings, :hotel_tin, :string
    add_column :e_invoice_settings, :hotel_brn, :string
    add_column :e_invoice_settings, :supplier_sst_registration_number, :string
  end
end
