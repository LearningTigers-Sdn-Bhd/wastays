# frozen_string_literal: true

class AddFinancialPaginationIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :booking_folios, [ :hotel_id, :updated_at, :id ],
      name: "idx_booking_folios_hotel_updated",
      order: { updated_at: :desc, id: :desc },
      algorithm: :concurrently
    add_index :ar_payments, [ :hotel_id, :received_at, :id ],
      name: "idx_ar_payments_hotel_received",
      order: { received_at: :desc, id: :desc },
      algorithm: :concurrently
    add_index :ar_payment_submissions, [ :hotel_id, :created_at, :id ],
      name: "idx_ar_payment_submissions_hotel_created",
      order: { created_at: :desc, id: :desc },
      algorithm: :concurrently
  end
end
