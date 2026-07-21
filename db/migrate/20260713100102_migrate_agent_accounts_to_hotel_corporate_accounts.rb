# frozen_string_literal: true

class MigrateAgentAccountsToHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  class MigrationAgentAccount < ApplicationRecord
    self.table_name = "agent_accounts"
  end

  class MigrationAccount < ApplicationRecord
    self.table_name = "accounts"
  end

  class MigrationHotel < ApplicationRecord
    self.table_name = "hotels"
  end

  class MigrationHotelCorporateAccount < ApplicationRecord
    self.table_name = "hotel_corporate_accounts"
  end

  class MigrationBooking < ApplicationRecord
    self.table_name = "bookings"
  end

  class MigrationBookingQuote < ApplicationRecord
    self.table_name = "booking_quotes"
  end

  def up
    add_column :bookings, :hotel_corporate_account_id, :bigint
    add_column :booking_quotes, :hotel_corporate_account_id, :bigint
    add_index :bookings, :hotel_corporate_account_id
    add_index :booking_quotes, :hotel_corporate_account_id

    say_with_time "Migrating agent_accounts into hotel_corporate_accounts" do
      MigrationAgentAccount.reset_column_information
      MigrationHotelCorporateAccount.reset_column_information

      MigrationAgentAccount.find_each do |agent_account|
        hotel = MigrationHotel.find(agent_account.hotel_id)

        account = MigrationAccount.create!(
          name: agent_account.name,
          slug: unique_account_slug(agent_account.name),
          status: "active",
          account_kind: "corporate"
        )

        hotel_corporate_account = MigrationHotelCorporateAccount.create!(
          hotel_id: agent_account.hotel_id,
          corporate_account_id: account.id,
          account_type: agent_account.account_type,
          agent_code: agent_account.agent_code,
          contact_email: agent_account.contact_email,
          contact_phone: agent_account.contact_phone,
          relationship_type: "standard",
          direct_bill_enabled: false,
          credit_currency: hotel.default_currency,
          status: "active"
        )

        MigrationBooking.where(agent_account_id: agent_account.id)
          .update_all(hotel_corporate_account_id: hotel_corporate_account.id)
        MigrationBookingQuote.where(agent_account_id: agent_account.id)
          .update_all(hotel_corporate_account_id: hotel_corporate_account.id)
      end
    end

    remove_foreign_key :bookings, :agent_accounts
    remove_foreign_key :booking_quotes, :agent_accounts
    remove_column :bookings, :agent_account_id
    remove_column :booking_quotes, :agent_account_id
    drop_table :agent_accounts

    add_foreign_key :bookings, :hotel_corporate_accounts
    add_foreign_key :booking_quotes, :hotel_corporate_accounts
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def unique_account_slug(name)
    base = name.to_s.parameterize.presence || "corporate-account"
    slug = base
    suffix = 2

    while MigrationAccount.exists?(slug: slug)
      slug = "#{base}-#{suffix}"
      suffix += 1
    end

    slug
  end
end
