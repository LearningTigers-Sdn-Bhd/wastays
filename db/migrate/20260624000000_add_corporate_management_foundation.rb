# frozen_string_literal: true

class AddCorporateManagementFoundation < ActiveRecord::Migration[8.0]
  ACCOUNT_KIND_CONSTRAINT = "accounts_account_kind_allowed"
  INVITATION_KIND_CONSTRAINT = "invitations_kind_allowed"
  INVITATION_ROLE_CONSTRAINT = "invitations_staff_role_required"
  INVITATION_CORPORATE_FIELDS_CONSTRAINT = "invitations_corporate_fields_required"
  RELATIONSHIP_TYPE_CONSTRAINT = "hotel_corporate_accounts_relationship_type_allowed"
  RELATIONSHIP_STATUS_CONSTRAINT = "hotel_corporate_accounts_status_allowed"

  def up
    add_column :accounts, :account_kind, :string, default: "hotel", null: false
    add_column :accounts, :corporate_type, :string
    add_index :accounts, :account_kind
    add_check_constraint :accounts,
      "account_kind IN ('hotel', 'corporate')",
      name: ACCOUNT_KIND_CONSTRAINT

    rename_table :staff_invitations, :invitations
    add_column :invitations, :kind, :string, default: "staff", null: false
    add_column :invitations, :metadata, :jsonb, default: {}, null: false
    change_column_null :invitations, :role_id, true
    add_index :invitations, :kind
    add_check_constraint :invitations,
      "kind IN ('staff', 'corporate')",
      name: INVITATION_KIND_CONSTRAINT
    add_check_constraint :invitations,
      "kind <> 'staff' OR role_id IS NOT NULL",
      name: INVITATION_ROLE_CONSTRAINT
    add_check_constraint :invitations,
      "kind <> 'corporate' OR (metadata ? 'relationship_type' AND metadata->>'relationship_type' IN ('standard', 'direct_bill'))",
      name: INVITATION_CORPORATE_FIELDS_CONSTRAINT

    create_table :hotel_corporate_accounts do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :corporate_account, null: false, foreign_key: { to_table: :accounts }
      t.string :relationship_type, default: "standard", null: false
      t.boolean :direct_bill_enabled, default: false, null: false
      t.decimal :credit_limit, precision: 12, scale: 2
      t.string :credit_currency, null: false
      t.integer :payment_terms_days
      t.string :status, default: "active", null: false
      t.datetime :suspended_at

      t.timestamps
    end

    add_index :hotel_corporate_accounts,
      [ :hotel_id, :corporate_account_id ],
      unique: true,
      name: "idx_hotel_corporate_accounts_unique_relationship"
    add_index :hotel_corporate_accounts, [ :corporate_account_id, :status ],
      name: "idx_hotel_corporate_accounts_on_account_and_status"
    add_index :hotel_corporate_accounts, [ :hotel_id, :status ],
      name: "idx_hotel_corporate_accounts_on_hotel_and_status"
    add_check_constraint :hotel_corporate_accounts,
      "relationship_type IN ('standard', 'direct_bill')",
      name: RELATIONSHIP_TYPE_CONSTRAINT
    add_check_constraint :hotel_corporate_accounts,
      "status IN ('active', 'suspended')",
      name: RELATIONSHIP_STATUS_CONSTRAINT
    add_check_constraint :hotel_corporate_accounts,
      "credit_limit IS NULL OR credit_limit >= 0",
      name: "hotel_corporate_accounts_credit_limit_nonnegative"
    add_check_constraint :hotel_corporate_accounts,
      "payment_terms_days IS NULL OR payment_terms_days >= 0",
      name: "hotel_corporate_accounts_payment_terms_nonnegative"

    ensure_case_insensitive_uniqueness!
  end

  def down
    remove_index :users, name: "index_users_on_lower_email", if_exists: true
    add_index :users, :email, name: "index_users_on_email", if_not_exists: true
    remove_index :accounts, name: "index_accounts_on_slug", if_exists: true
    add_index :accounts, :slug, name: "index_accounts_on_slug", if_not_exists: true

    drop_table :hotel_corporate_accounts

    remove_check_constraint :invitations, name: INVITATION_CORPORATE_FIELDS_CONSTRAINT
    remove_check_constraint :invitations, name: INVITATION_ROLE_CONSTRAINT
    remove_check_constraint :invitations, name: INVITATION_KIND_CONSTRAINT
    remove_index :invitations, :kind
    remove_column :invitations, :metadata
    remove_column :invitations, :kind
    change_column_null :invitations, :role_id, false
    rename_table :invitations, :staff_invitations

    remove_check_constraint :accounts, name: ACCOUNT_KIND_CONSTRAINT
    remove_index :accounts, :account_kind
    remove_column :accounts, :corporate_type
    remove_column :accounts, :account_kind
  end

  private

  def ensure_case_insensitive_uniqueness!
    duplicate_emails = connection.select_values(<<~SQL.squish)
      SELECT LOWER(email)
      FROM users
      GROUP BY LOWER(email)
      HAVING COUNT(*) > 1
    SQL
    raise ActiveRecord::MigrationError, "Duplicate user emails found: #{duplicate_emails.join(', ')}" if duplicate_emails.any?

    duplicate_slugs = connection.select_values(<<~SQL.squish)
      SELECT slug
      FROM accounts
      WHERE slug IS NOT NULL
      GROUP BY slug
      HAVING COUNT(*) > 1
    SQL
    raise ActiveRecord::MigrationError, "Duplicate account slugs found: #{duplicate_slugs.join(', ')}" if duplicate_slugs.any?

    remove_index :users, name: "index_users_on_email", if_exists: true
    add_index :users, "LOWER(email)", unique: true, name: "index_users_on_lower_email"

    remove_index :accounts, name: "index_accounts_on_slug", if_exists: true
    add_index :accounts, :slug, unique: true, name: "index_accounts_on_slug"
  end
end
