# frozen_string_literal: true

class AddTransactionCodeToDeposits < ActiveRecord::Migration[8.0]
  def up
    add_reference :deposits, :transaction_code, foreign_key: true

    execute <<~SQL.squish
      INSERT INTO transaction_codes (
        hotel_id,
        system_key,
        code,
        name,
        kind,
        category,
        active,
        system_required,
        gl_account_code,
        created_at,
        updated_at
      )
      SELECT
        hotels.id,
        'security_deposit',
        (
          SELECT candidate_code
          FROM (
            SELECT suffix, CASE WHEN suffix = 1 THEN 'SECDEP' ELSE 'SECDEP_' || suffix END AS candidate_code
            FROM generate_series(1, 1000) AS suffix
          ) candidates
          WHERE NOT EXISTS (
            SELECT 1
            FROM transaction_codes existing_codes
            WHERE existing_codes.hotel_id = hotels.id
              AND existing_codes.code = candidates.candidate_code
          )
          ORDER BY suffix
          LIMIT 1
        ),
        'Security Deposit',
        'payment',
        'security_deposit',
        TRUE,
        TRUE,
        COALESCE(hotel_general_ledger_maps.gl_code, '2030'),
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM hotels
      LEFT JOIN hotel_general_ledger_maps
        ON hotel_general_ledger_maps.hotel_id = hotels.id
       AND hotel_general_ledger_maps.transaction_category = 'security_deposits'
      WHERE NOT EXISTS (
        SELECT 1
        FROM transaction_codes
        WHERE transaction_codes.hotel_id = hotels.id
          AND transaction_codes.system_key = 'security_deposit'
      )
    SQL

    execute <<~SQL.squish
      UPDATE deposits
      SET transaction_code_id = transaction_codes.id,
          updated_at = CURRENT_TIMESTAMP
      FROM transaction_codes
      WHERE transaction_codes.hotel_id = deposits.hotel_id
        AND transaction_codes.system_key = 'security_deposit'
        AND deposits.transaction_code_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE deposits
      SET status = 'held',
          updated_at = CURRENT_TIMESTAMP
      WHERE hold_type = 'security'
        AND status = 'collected'
    SQL

    execute <<~SQL.squish
      UPDATE bookings
      SET deposit_status = 'held',
          updated_at = CURRENT_TIMESTAMP
      WHERE deposit_status = 'collected'
        AND EXISTS (
          SELECT 1
          FROM deposits
          WHERE deposits.booking_id = bookings.id
            AND deposits.hold_type = 'security'
            AND deposits.status = 'held'
        )
    SQL

    change_column_null :deposits, :transaction_code_id, false
  end

  def down
    change_column_null :deposits, :transaction_code_id, true

    execute <<~SQL.squish
      UPDATE deposits
      SET status = 'collected',
          updated_at = CURRENT_TIMESTAMP
      WHERE hold_type = 'security'
        AND status = 'held'
    SQL

    execute <<~SQL.squish
      UPDATE bookings
      SET deposit_status = 'collected',
          updated_at = CURRENT_TIMESTAMP
      WHERE deposit_status = 'held'
        AND EXISTS (
          SELECT 1
          FROM deposits
          WHERE deposits.booking_id = bookings.id
            AND deposits.hold_type = 'security'
            AND deposits.status = 'collected'
        )
    SQL

    execute <<~SQL.squish
      DELETE FROM transaction_codes
      WHERE system_key = 'security_deposit'
        AND NOT EXISTS (
          SELECT 1
          FROM deposits
          WHERE deposits.transaction_code_id = transaction_codes.id
        )
    SQL

    remove_reference :deposits, :transaction_code, foreign_key: true
  end
end
