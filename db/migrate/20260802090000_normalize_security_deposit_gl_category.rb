# frozen_string_literal: true

class NormalizeSecurityDepositGlCategory < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      DELETE FROM hotel_general_ledger_maps singular
      USING hotel_general_ledger_maps plural
      WHERE singular.hotel_id = plural.hotel_id
        AND singular.transaction_category = 'security_deposit'
        AND plural.transaction_category = 'security_deposits'
    SQL

    execute <<~SQL
      UPDATE hotel_general_ledger_maps
      SET transaction_category = 'security_deposit'
      WHERE transaction_category = 'security_deposits'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE hotel_general_ledger_maps
      SET transaction_category = 'security_deposits'
      WHERE transaction_category = 'security_deposit'
    SQL
  end
end
