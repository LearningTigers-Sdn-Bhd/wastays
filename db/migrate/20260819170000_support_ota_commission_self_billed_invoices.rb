# frozen_string_literal: true

# An OTA's commission is billed to the hotel for a period, not for one stay, so
# these documents are not booking-scoped. Agoda and Booking.com are overseas
# entities, so LHDN requires the hotel to self-bill for the commission as an
# importation of services in order to deduct it.
class SupportOtaCommissionSelfBilledInvoices < ActiveRecord::Migration[8.1]
  def change
    change_column_null :e_invoice_submissions, :booking_id, true

    add_column :e_invoice_submissions, :ota_source_key, :string
    add_column :e_invoice_submissions, :period_start, :date

    add_index :e_invoice_submissions,
              [ :hotel_id, :ota_source_key, :period_start ],
              unique: true,
              where: "document_scenario = 'ota_commission_self_billed' AND status <> 'cancelled'",
              name: "index_e_invoice_submissions_on_ota_commission_period"

    # Who the OTA is, for the supplier side of that self-billed document.
    add_column :booking_sources, :legal_name, :string
    add_column :booking_sources, :tax_country_code, :string
    add_column :booking_sources, :self_bill_commission, :boolean, default: false, null: false
  end
end
