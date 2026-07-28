# frozen_string_literal: true

class EnforceYearlyDocumentSequences < ActiveRecord::Migration[8.0]
  def change
    change_column_null :bookings, :reservation_number, false
    change_column_null :bookings, :reservation_year, false
    change_column_null :group_bookings, :reservation_year, false
    change_column_null :booking_folios, :folio_number, false
    change_column_null :booking_folios, :folio_year, false
    change_column_null :ar_invoices, :invoice_year, false
    change_column_null :receipts, :receipt_year, false

    add_check_constraint :hotel_counters,
      "sequence_year BETWEEN 2000 AND 2099",
      name: "hotel_counters_sequence_year_range"
    add_check_constraint :bookings,
      "(guest_registration_number IS NULL) = (guest_registration_year IS NULL)",
      name: "bookings_guest_registration_year_pair"
    add_check_constraint :bookings,
      "(tourism_tax_voucher_number IS NULL) = (tourism_tax_voucher_year IS NULL)",
      name: "bookings_tourism_voucher_year_pair"
    add_check_constraint :booking_folios,
      "(invoice_number IS NULL) = (invoice_year IS NULL)",
      name: "booking_folios_invoice_year_pair"
  end
end
