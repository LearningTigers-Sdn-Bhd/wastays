# frozen_string_literal: true

class RenameGlMapPenaltyTransactionCategories < ActiveRecord::Migration[7.1]
  def up
    HotelGeneralLedgerMap.where(transaction_category: "no_show_penalty").update_all(transaction_category: "no_show_charge")
    HotelGeneralLedgerMap.where(transaction_category: "late_checkout_penalty").update_all(transaction_category: "late_checkout_charge")
    HotelGeneralLedgerMap.where(transaction_category: "early_departure_penalty").update_all(transaction_category: "early_departure_charge")
  end

  def down
    HotelGeneralLedgerMap.where(transaction_category: "no_show_charge").update_all(transaction_category: "no_show_penalty")
    HotelGeneralLedgerMap.where(transaction_category: "late_checkout_charge").update_all(transaction_category: "late_checkout_penalty")
    HotelGeneralLedgerMap.where(transaction_category: "early_departure_charge").update_all(transaction_category: "early_departure_penalty")
  end
end
