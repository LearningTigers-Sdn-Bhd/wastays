# frozen_string_literal: true

class SyncTaxTransactionCodeActiveStates < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL.squish)
      UPDATE transaction_codes
      SET active = hotels.sst_enabled,
          updated_at = CURRENT_TIMESTAMP
      FROM hotels
      WHERE transaction_codes.hotel_id = hotels.id
        AND transaction_codes.system_key = 'sst_tax'
    SQL

    execute(<<~SQL.squish)
      UPDATE transaction_codes
      SET active = hotels.tourism_tax_enabled,
          updated_at = CURRENT_TIMESTAMP
      FROM hotels
      WHERE transaction_codes.hotel_id = hotels.id
        AND transaction_codes.system_key = 'tourism_tax'
    SQL

    execute(<<~SQL.squish)
      UPDATE transaction_codes
      SET active = hotel_taxes.enabled,
          updated_at = CURRENT_TIMESTAMP
      FROM hotel_taxes
      WHERE transaction_codes.id = hotel_taxes.transaction_code_id
    SQL
  end

  def down
    execute(<<~SQL.squish)
      UPDATE transaction_codes
      SET active = TRUE,
          updated_at = CURRENT_TIMESTAMP
      WHERE kind = 'tax'
    SQL
  end
end
