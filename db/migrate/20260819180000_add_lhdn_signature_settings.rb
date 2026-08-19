# frozen_string_literal: true

# LHDN document version 1.1 carries a digital signature; 1.0 does not. Building
# the 1.1 shape either way and toggling the signature block means the switch is
# a setting rather than a rewrite when LHDN mandates 1.1.
class AddLhdnSignatureSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :e_invoice_settings, :signature_enabled, :boolean, default: false, null: false
    add_column :e_invoice_settings, :signing_certificate, :text
    add_column :e_invoice_settings, :signing_private_key, :text
  end
end
