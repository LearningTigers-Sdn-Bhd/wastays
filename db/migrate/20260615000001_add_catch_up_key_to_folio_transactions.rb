# frozen_string_literal: true

class AddCatchUpKeyToFolioTransactions < ActiveRecord::Migration[8.0]
  class MigrationFolioTransaction < ActiveRecord::Base
    self.table_name = "folio_transactions"
  end

  def up
    add_column :folio_transactions, :catch_up_key, :string

    backfill_catch_up_keys

    duplicate_keys = duplicate_catch_up_keys
    if duplicate_keys.any?
      examples = duplicate_keys.first(10).map { |folio_id, key| "booking_folio_id=#{folio_id}, catch_up_key=#{key}" }.join("; ")
      raise ActiveRecord::IrreversibleMigration,
        "Duplicate catch-up folio transactions exist. Resolve before adding unique index: #{examples}"
    end

    add_catch_up_index
  end

  def down
    remove_index :folio_transactions, name: "index_folio_transactions_on_folio_and_catch_up_key"
    remove_column :folio_transactions, :catch_up_key
  end

  private

  def backfill_catch_up_keys
    execute <<~SQL.squish
      UPDATE folio_transactions
      SET catch_up_key = metadata->>'catch_up_key'
      WHERE catch_up_key IS NULL
        AND metadata ? 'catch_up_key'
        AND NULLIF(metadata->>'catch_up_key', '') IS NOT NULL
    SQL
  end

  def duplicate_catch_up_keys
    MigrationFolioTransaction
      .where.not(catch_up_key: nil)
      .group(:booking_folio_id, :catch_up_key)
      .having("COUNT(*) > 1")
      .pluck(:booking_folio_id, :catch_up_key)
  end

  def add_catch_up_index

    add_index :folio_transactions,
      [ :booking_folio_id, :catch_up_key ],
      unique: true,
      where: "catch_up_key IS NOT NULL",
      name: "index_folio_transactions_on_folio_and_catch_up_key"
  end
end
