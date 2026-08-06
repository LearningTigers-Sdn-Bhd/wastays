# frozen_string_literal: true

class UnifyDeposits < ActiveRecord::Migration[8.0]
  def up
    validate_legacy_provenance!
    rename_legacy_tables!
    create_unified_tables!
    backfill_security_deposits!
    backfill_group_deposits!
    backfill_group_allocations!
    backfill_group_refunds!
    finalize_backfilled_statuses!
    drop_legacy_tables!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Unified deposit movements cannot be converted back to the legacy schemas."
  end

  private

  def rename_legacy_tables!
    rename_table :deposits, :legacy_security_deposits
    rename_table :group_deposit_allocations, :legacy_group_deposit_allocations
    rename_table :group_deposits, :legacy_group_deposits
  end

  def create_unified_tables!
    create_table :deposits do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: true, foreign_key: true
      t.references :group_booking, null: true, foreign_key: true
      t.references :hotel_corporate_account, null: true, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true
      t.references :received_by, null: true, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :status, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false
      t.string :payment_method, null: false
      t.string :external_reference
      t.datetime :received_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :deposits, [ :hotel_id, :kind, :status ]
    add_index :deposits, [ :hotel_id, :booking_id, :external_reference ], unique: true,
      where: "booking_id IS NOT NULL AND external_reference IS NOT NULL",
      name: "idx_deposits_booking_reference"
    add_index :deposits, [ :hotel_id, :group_booking_id, :external_reference ], unique: true,
      where: "group_booking_id IS NOT NULL AND external_reference IS NOT NULL",
      name: "idx_deposits_group_reference"
    add_check_constraint :deposits, "amount > 0", name: "deposits_amount_positive"
    add_check_constraint :deposits,
      "((booking_id IS NOT NULL)::integer + (group_booking_id IS NOT NULL)::integer) = 1",
      name: "deposits_exactly_one_owner"
    add_check_constraint :deposits, "kind IN ('security', 'prepayment')", name: "deposits_kind_allowed"
    add_check_constraint :deposits,
      "status IN ('pending', 'held', 'available', 'settled', 'released', 'refunded', 'cancelled', 'failed')",
      name: "deposits_status_allowed"

    create_table :deposit_movements do |t|
      t.references :deposit, null: false, foreign_key: true
      t.references :booking_folio, null: true, foreign_key: true
      t.references :folio_transaction, null: true, foreign_key: true, index: false
      t.references :performed_by, null: true, foreign_key: { to_table: :users }
      t.references :reversal_of, null: true, foreign_key: { to_table: :deposit_movements }, index: false
      t.string :movement_type, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :payment_method
      t.string :external_reference
      t.string :operation_key
      t.text :reason
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :deposit_movements, [ :deposit_id, :occurred_at ]
    add_index :deposit_movements, :folio_transaction_id, unique: true, where: "folio_transaction_id IS NOT NULL"
    add_index :deposit_movements, :reversal_of_id, unique: true,
      where: "reversal_of_id IS NOT NULL", name: "idx_deposit_movements_one_reversal"
    add_index :deposit_movements, :operation_key, unique: true, where: "operation_key IS NOT NULL"
    add_check_constraint :deposit_movements, "amount > 0", name: "deposit_movements_amount_positive"
    add_check_constraint :deposit_movements,
      "movement_type IN ('hold', 'receive', 'apply', 'reverse', 'release', 'refund')",
      name: "deposit_movements_type_allowed"
    add_check_constraint :deposit_movements, <<~SQL.squish, name: "deposit_movements_target_shape"
      (movement_type IN ('apply', 'reverse') AND booking_folio_id IS NOT NULL AND folio_transaction_id IS NOT NULL)
      OR
      (movement_type NOT IN ('apply', 'reverse') AND booking_folio_id IS NULL AND folio_transaction_id IS NULL)
    SQL
    add_check_constraint :deposit_movements, <<~SQL.squish, name: "deposit_movements_reversal_shape"
      (movement_type = 'reverse' AND reversal_of_id IS NOT NULL)
      OR
      (movement_type <> 'reverse' AND reversal_of_id IS NULL)
    SQL
  end

  def backfill_security_deposits!
    execute <<~SQL
      INSERT INTO deposits (
        hotel_id, booking_id, transaction_code_id, received_by_id, kind, status,
        amount, currency, payment_method, external_reference, received_at, metadata, created_at, updated_at
      )
      SELECT
        legacy.hotel_id,
        legacy.booking_id,
        COALESCE(legacy.transaction_code_id, codes.id),
        legacy.user_id,
        'security',
        CASE legacy.status
          WHEN 'pending' THEN 'pending'
          WHEN 'failed' THEN 'failed'
          WHEN 'released' THEN 'released'
          WHEN 'forfeited' THEN 'released'
          ELSE 'held'
        END,
        legacy.amount,
        legacy.currency,
        COALESCE(NULLIF(legacy.payment_method, ''), 'cash'),
        legacy.external_reference,
        COALESCE(legacy.collected_at, legacy.authorized_at, legacy.created_at),
        COALESCE(legacy.metadata, '{}'::jsonb) || jsonb_build_object(
          'legacy_security_deposit_id', legacy.id,
          'legacy_status', legacy.status,
          'legacy_booking_folio_id', legacy.booking_folio_id
        ),
        legacy.created_at,
        legacy.updated_at
      FROM legacy_security_deposits legacy
      LEFT JOIN LATERAL (
        SELECT id FROM transaction_codes
        WHERE hotel_id = legacy.hotel_id AND system_key = 'security_deposit'
        ORDER BY id LIMIT 1
      ) codes ON TRUE
    SQL

    execute <<~SQL
      INSERT INTO deposit_movements (
        deposit_id, performed_by_id, movement_type, amount, payment_method, external_reference,
        operation_key, reason, occurred_at, metadata, created_at, updated_at
      )
      SELECT
        deposit.id,
        legacy.user_id,
        'hold',
        legacy.amount,
        COALESCE(NULLIF(legacy.payment_method, ''), 'cash'),
        legacy.external_reference,
        'legacy-security:' || legacy.id || ':hold',
        NULL,
        COALESCE(legacy.authorized_at, legacy.collected_at, legacy.created_at),
        jsonb_build_object('legacy_security_deposit_id', legacy.id),
        legacy.created_at,
        legacy.updated_at
      FROM legacy_security_deposits legacy
      JOIN deposits deposit ON deposit.metadata->>'legacy_security_deposit_id' = legacy.id::text
    SQL

    execute <<~SQL
      INSERT INTO deposit_movements (
        deposit_id, performed_by_id, movement_type, amount, payment_method, external_reference,
        operation_key, reason, occurred_at, metadata, created_at, updated_at
      )
      SELECT
        deposit.id,
        legacy.user_id,
        'release',
        legacy.amount,
        COALESCE(NULLIF(legacy.payment_method, ''), 'cash'),
        legacy.external_reference,
        'legacy-security:' || legacy.id || ':release',
        CASE WHEN legacy.status = 'forfeited'
          THEN 'Legacy forfeiture: deposit liability cleared; original revenue posting was not linked.'
          ELSE 'Migrated legacy security deposit release.'
        END,
        COALESCE(legacy.released_at, legacy.forfeited_at, legacy.updated_at),
        jsonb_build_object('legacy_security_deposit_id', legacy.id, 'legacy_status', legacy.status),
        legacy.updated_at,
        legacy.updated_at
      FROM legacy_security_deposits legacy
      JOIN deposits deposit ON deposit.metadata->>'legacy_security_deposit_id' = legacy.id::text
      WHERE legacy.status IN ('released', 'forfeited')
    SQL
  end

  def backfill_group_deposits!
    execute <<~SQL
      INSERT INTO deposits (
        hotel_id, group_booking_id, hotel_corporate_account_id, transaction_code_id, received_by_id,
        kind, status, amount, currency, payment_method, external_reference, received_at, metadata, created_at, updated_at
      )
      SELECT
        legacy.hotel_id,
        legacy.group_booking_id,
        legacy.hotel_corporate_account_id,
        codes.id,
        legacy.received_by_id,
        'prepayment',
        CASE WHEN legacy.status = 'cancelled' THEN 'cancelled' ELSE 'available' END,
        legacy.amount,
        legacy.currency,
        legacy.payment_method,
        legacy.external_reference,
        legacy.received_at,
        COALESCE(legacy.metadata, '{}'::jsonb) || jsonb_build_object(
          'legacy_group_deposit_id', legacy.id,
          'legacy_status', legacy.status
        ),
        legacy.created_at,
        legacy.updated_at
      FROM legacy_group_deposits legacy
      JOIN LATERAL (
        SELECT id FROM transaction_codes
        WHERE hotel_id = legacy.hotel_id AND category = 'booking_payment'
        ORDER BY (system_key = 'bank_payment') DESC, id
        LIMIT 1
      ) codes ON TRUE
    SQL

    execute <<~SQL
      INSERT INTO deposit_movements (
        deposit_id, performed_by_id, movement_type, amount, payment_method, external_reference,
        operation_key, occurred_at, metadata, created_at, updated_at
      )
      SELECT
        deposit.id,
        legacy.received_by_id,
        'receive',
        legacy.amount,
        legacy.payment_method,
        legacy.external_reference,
        'legacy-group:' || legacy.id || ':receive',
        legacy.received_at,
        jsonb_build_object('legacy_group_deposit_id', legacy.id),
        legacy.created_at,
        legacy.updated_at
      FROM legacy_group_deposits legacy
      JOIN deposits deposit ON deposit.metadata->>'legacy_group_deposit_id' = legacy.id::text
    SQL
  end

  def backfill_group_allocations!
    execute <<~SQL
      INSERT INTO deposit_movements (
        deposit_id, booking_folio_id, folio_transaction_id, performed_by_id, movement_type, amount,
        operation_key, occurred_at, metadata, created_at, updated_at
      )
      SELECT
        deposit.id,
        allocation.booking_folio_id,
        allocation.folio_transaction_id,
        allocation.allocated_by_id,
        'apply',
        allocation.amount,
        'legacy-group-allocation:' || allocation.id || ':apply',
        allocation.allocated_at,
        COALESCE(allocation.metadata, '{}'::jsonb) || jsonb_build_object(
          'legacy_group_deposit_allocation_id', allocation.id,
          'legacy_status', allocation.status
        ),
        allocation.created_at,
        allocation.updated_at
      FROM legacy_group_deposit_allocations allocation
      JOIN deposits deposit ON deposit.metadata->>'legacy_group_deposit_id' = allocation.group_deposit_id::text
      WHERE allocation.reversal_of_id IS NULL
    SQL

    execute <<~SQL
      INSERT INTO deposit_movements (
        deposit_id, booking_folio_id, folio_transaction_id, performed_by_id, reversal_of_id,
        movement_type, amount, operation_key, reason, occurred_at, metadata, created_at, updated_at
      )
      SELECT
        deposit.id,
        reversal.booking_folio_id,
        reversal.folio_transaction_id,
        reversal.allocated_by_id,
        application.id,
        'reverse',
        reversal.amount,
        'legacy-group-allocation:' || reversal.id || ':reverse',
        COALESCE(reversal.metadata->>'reason', 'Migrated legacy allocation reversal.'),
        COALESCE(reversal.reversed_at, reversal.allocated_at),
        COALESCE(reversal.metadata, '{}'::jsonb) || jsonb_build_object(
          'legacy_group_deposit_allocation_id', reversal.id
        ),
        reversal.created_at,
        reversal.updated_at
      FROM legacy_group_deposit_allocations reversal
      JOIN deposits deposit ON deposit.metadata->>'legacy_group_deposit_id' = reversal.group_deposit_id::text
      JOIN deposit_movements application
        ON application.metadata->>'legacy_group_deposit_allocation_id' = reversal.reversal_of_id::text
       AND application.movement_type = 'apply'
      WHERE reversal.reversal_of_id IS NOT NULL
    SQL
  end

  def backfill_group_refunds!
    execute <<~SQL
      INSERT INTO deposit_movements (
        deposit_id, performed_by_id, movement_type, amount, payment_method, operation_key,
        reason, occurred_at, metadata, created_at, updated_at
      )
      SELECT
        deposit.id,
        legacy.received_by_id,
        'refund',
        legacy.refunded_amount,
        legacy.payment_method,
        'legacy-group:' || legacy.id || ':refund',
        'Migrated legacy group deposit refund.',
        COALESCE(legacy.refunded_at, legacy.updated_at),
        jsonb_build_object('legacy_group_deposit_id', legacy.id),
        legacy.updated_at,
        legacy.updated_at
      FROM legacy_group_deposits legacy
      JOIN deposits deposit ON deposit.metadata->>'legacy_group_deposit_id' = legacy.id::text
      WHERE legacy.refunded_amount > 0
    SQL
  end

  def finalize_backfilled_statuses!
    execute <<~SQL
      UPDATE deposits deposit
      SET status = CASE
        WHEN deposit.status IN ('pending', 'failed', 'cancelled') THEN deposit.status
        WHEN totals.available > 0 THEN CASE WHEN deposit.kind = 'security' THEN 'held' ELSE 'available' END
        WHEN totals.applied > 0 THEN 'settled'
        WHEN deposit.kind = 'security' THEN 'released'
        ELSE 'refunded'
      END
      FROM (
        SELECT
          deposit.id,
          deposit.amount
            - COALESCE(SUM(movement.amount) FILTER (WHERE movement.movement_type = 'apply'), 0)
            + COALESCE(SUM(movement.amount) FILTER (WHERE movement.movement_type = 'reverse'), 0)
            - COALESCE(SUM(movement.amount) FILTER (WHERE movement.movement_type IN ('release', 'refund')), 0) AS available,
          COALESCE(SUM(movement.amount) FILTER (WHERE movement.movement_type = 'apply'), 0)
            - COALESCE(SUM(movement.amount) FILTER (WHERE movement.movement_type = 'reverse'), 0) AS applied
        FROM deposits deposit
        LEFT JOIN deposit_movements movement ON movement.deposit_id = deposit.id
        GROUP BY deposit.id, deposit.amount
      ) totals
      WHERE totals.id = deposit.id
    SQL
  end

  def drop_legacy_tables!
    drop_table :legacy_group_deposit_allocations
    drop_table :legacy_group_deposits
    drop_table :legacy_security_deposits
  end

  def validate_legacy_provenance!
    missing_group_codes = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM group_deposits deposit
      WHERE NOT EXISTS (
        SELECT 1 FROM transaction_codes code
        WHERE code.hotel_id = deposit.hotel_id AND code.category = 'booking_payment'
      )
    SQL
    missing_security_codes = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM deposits deposit
      WHERE deposit.transaction_code_id IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM transaction_codes code
          WHERE code.hotel_id = deposit.hotel_id AND code.system_key = 'security_deposit'
        )
    SQL
    missing_transactions = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM group_deposit_allocations
      WHERE folio_transaction_id IS NULL
    SQL
    orphaned_postings = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM folio_transactions folio_tx
      WHERE (folio_tx.metadata->>'posting_source' = 'group_deposit_allocation' OR folio_tx.metadata ? 'group_deposit_id')
        AND NOT EXISTS (
          SELECT 1 FROM group_deposit_allocations allocation
          WHERE allocation.folio_transaction_id = folio_tx.id
        )
    SQL
    duplicate_security_references = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (
        SELECT hotel_id, booking_id, external_reference
        FROM deposits
        WHERE external_reference IS NOT NULL
        GROUP BY hotel_id, booking_id, external_reference
        HAVING COUNT(*) > 1
      ) duplicates
    SQL
    return if missing_group_codes.zero? && missing_security_codes.zero? && missing_transactions.zero? &&
      orphaned_postings.zero? && duplicate_security_references.zero?

    raise ActiveRecord::IrreversibleMigration,
      "Unified deposit backfill cannot preserve provenance: #{missing_group_codes} group deposits and " \
      "#{missing_security_codes} security deposits lack transaction codes, " \
      "#{missing_transactions} allocations lack folio transactions, #{orphaned_postings} folio postings lack allocations, " \
      "and #{duplicate_security_references} booking/reference combinations are duplicated."
  end
end
