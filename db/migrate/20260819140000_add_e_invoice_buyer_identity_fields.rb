# frozen_string_literal: true

# LHDN needs a state code (not a city name), a postcode, and - for anyone who
# wants to claim the invoice - the buyer's own TIN. Without these every buyer
# files as general public, which is useless to a business.
class AddEInvoiceBuyerIdentityFields < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :guest_state_code, :string
    add_column :bookings, :guest_postal_code, :string
    add_column :bookings, :guest_tin, :string

    add_column :guests, :state_code, :string
    add_column :guests, :postal_code, :string
    add_column :guests, :tin, :string

    add_column :hotel_corporate_accounts, :tin, :string
    add_column :hotel_corporate_accounts, :brn, :string
    add_column :hotel_corporate_accounts, :sst_registration_number, :string

    # Go-forward only: a hotel files from the moment it switched e-invoicing on,
    # so enabling the feature never retroactively sweeps in historical stays.
    add_column :e_invoice_settings, :effective_from, :datetime
  end
end
