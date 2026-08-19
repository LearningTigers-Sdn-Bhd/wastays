# frozen_string_literal: true

# WAStays is under the RM1m threshold, so it does not issue e-invoices as a
# supplier. Each hotel files its own under its own LHDN credentials, with
# WAStays operating the software on their behalf. That means the API
# credentials belong to the hotel, not to us.
class AddHotelLhdnCredentialsToEInvoiceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :e_invoice_settings, :client_id, :text
    add_column :e_invoice_settings, :client_secret, :text
    add_column :e_invoice_settings, :api_environment, :string, default: "sandbox", null: false
  end
end
