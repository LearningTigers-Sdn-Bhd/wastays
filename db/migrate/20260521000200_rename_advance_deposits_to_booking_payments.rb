# frozen_string_literal: true

class RenameAdvanceDepositsToBookingPayments < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE folio_transactions
      SET category = 'booking_payment'
      WHERE category = 'advance_deposit'
    SQL

    execute <<~SQL.squish
      UPDATE hotel_general_ledger_maps
      SET transaction_category = 'booking_payment', description = 'Booking Payment Liability'
      WHERE transaction_category = 'advance_deposit'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE folio_transactions
      SET category = 'advance_deposit'
      WHERE category = 'booking_payment'
    SQL

    execute <<~SQL.squish
      UPDATE hotel_general_ledger_maps
      SET transaction_category = 'advance_deposit', description = 'Advance Deposit Liability'
      WHERE transaction_category = 'booking_payment'
    SQL
  end
end
