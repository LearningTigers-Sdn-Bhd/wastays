# frozen_string_literal: true

class MoveCorporateTypeToHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  def up
    add_column :hotel_corporate_accounts, :corporate_type, :string

    unlinked_corporate_type_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM accounts
      WHERE account_kind = 'corporate'
        AND corporate_type IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM hotel_corporate_accounts
          WHERE hotel_corporate_accounts.corporate_account_id = accounts.id
        )
    SQL

    if unlinked_corporate_type_count.positive?
      raise ActiveRecord::MigrationError,
        "Cannot move corporate_type for #{unlinked_corporate_type_count} unlinked corporate account(s)."
    end

    execute <<~SQL.squish
      UPDATE hotel_corporate_accounts
      SET corporate_type = accounts.corporate_type
      FROM accounts
      WHERE accounts.id = hotel_corporate_accounts.corporate_account_id
    SQL

    remove_column :accounts, :corporate_type
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "corporate_type is now per hotel relationship and cannot be safely collapsed back to accounts"
  end
end
