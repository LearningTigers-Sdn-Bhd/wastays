# frozen_string_literal: true

class AddMultiFolioFoundation < ActiveRecord::Migration[8.0]
  FOLIO_WINDOW_PERMISSIONS = {
    "manage_folio_windows" => "Manage Folio Windows",
    "manage_folio_movements" => "Manage Folio Movements"
  }.freeze

  def up
    remove_check_constraint :booking_folios, name: "booking_folios_status_allowed"
    remove_index :booking_folios, name: "index_booking_folios_on_booking_id"

    change_table :booking_folios, bulk: true do |t|
      t.string :name
      t.string :folio_type, null: false, default: "guest"
      t.string :payer_type, null: false, default: "guest"
      t.bigint :payer_id
      t.boolean :is_primary, null: false, default: false
      t.string :currency
      t.datetime :opened_at
      t.datetime :closed_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :closed_by, foreign_key: { to_table: :users }
    end

    execute <<~SQL.squish
      UPDATE booking_folios
      SET is_primary = TRUE,
          name = COALESCE(booking_folios.name, 'Guest Folio'),
          currency = COALESCE(booking_folios.currency, bookings.currency, hotels.default_currency, 'MYR'),
          opened_at = COALESCE(booking_folios.opened_at, booking_folios.created_at)
      FROM bookings, hotels
      WHERE booking_folios.booking_id = bookings.id
        AND booking_folios.hotel_id = hotels.id
    SQL

    change_column_null :booking_folios, :name, false
    change_column_null :booking_folios, :currency, false
    change_column_null :booking_folios, :opened_at, false

    add_index :booking_folios, :booking_id, name: "index_booking_folios_on_booking_id"
    add_index :booking_folios, [ :booking_id, :is_primary ],
      unique: true,
      where: "is_primary",
      name: "index_booking_folios_on_primary_booking"
    add_index :booking_folios, [ :hotel_id, :status ], name: "index_booking_folios_on_hotel_id_and_status"
    add_index :booking_folios, [ :hotel_id, :folio_type ], name: "index_booking_folios_on_hotel_id_and_folio_type"
    add_check_constraint :booking_folios,
      "status IN ('open', 'closed', 'voided')",
      name: "booking_folios_status_allowed"
    add_check_constraint :booking_folios,
      "folio_type IN ('guest', 'company', 'custom', 'group', 'master', 'house')",
      name: "booking_folios_folio_type_allowed"
    add_check_constraint :booking_folios,
      "payer_type IN ('guest', 'company', 'custom')",
      name: "booking_folios_payer_type_allowed"

    create_table :folio_operation_logs do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :operation_type, null: false
      t.references :source_folio, foreign_key: { to_table: :booking_folios }
      t.references :target_folio, foreign_key: { to_table: :booking_folios }
      t.references :source_transaction, foreign_key: { to_table: :folio_transactions }
      t.references :target_transaction, foreign_key: { to_table: :folio_transactions }
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency
      t.string :operation_key
      t.text :reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :folio_operation_logs, [ :hotel_id, :booking_id, :created_at ], name: "idx_folio_operation_logs_on_booking_time"
    add_index :folio_operation_logs, :operation_type
    add_index :folio_operation_logs, :operation_key

    change_table :folio_transactions, bulk: true do |t|
      t.references :parent_transaction, foreign_key: { to_table: :folio_transactions }
      t.references :split_from_transaction, foreign_key: { to_table: :folio_transactions }
      t.references :moved_from_transaction, foreign_key: { to_table: :folio_transactions }
      t.string :transfer_group_id
      t.string :operation_key
    end

    add_index :folio_transactions, :transfer_group_id
    add_index :folio_transactions, :operation_key

    seed_permissions!
  end

  def down
    remove_index :folio_transactions, :operation_key
    remove_index :folio_transactions, :transfer_group_id
    remove_reference :folio_transactions, :parent_transaction, foreign_key: { to_table: :folio_transactions }
    remove_reference :folio_transactions, :split_from_transaction, foreign_key: { to_table: :folio_transactions }
    remove_reference :folio_transactions, :moved_from_transaction, foreign_key: { to_table: :folio_transactions }
    remove_column :folio_transactions, :transfer_group_id
    remove_column :folio_transactions, :operation_key

    drop_table :folio_operation_logs

    remove_check_constraint :booking_folios, name: "booking_folios_payer_type_allowed"
    remove_check_constraint :booking_folios, name: "booking_folios_folio_type_allowed"
    remove_check_constraint :booking_folios, name: "booking_folios_status_allowed"
    remove_index :booking_folios, name: "index_booking_folios_on_hotel_id_and_folio_type"
    remove_index :booking_folios, name: "index_booking_folios_on_hotel_id_and_status"
    remove_index :booking_folios, name: "index_booking_folios_on_primary_booking"
    remove_index :booking_folios, name: "index_booking_folios_on_booking_id"

    add_index :booking_folios, :booking_id, unique: true, name: "index_booking_folios_on_booking_id"
    add_check_constraint :booking_folios,
      "status IN ('open', 'closed')",
      name: "booking_folios_status_allowed"

    remove_reference :booking_folios, :closed_by, foreign_key: { to_table: :users }
    remove_reference :booking_folios, :created_by, foreign_key: { to_table: :users }
    remove_column :booking_folios, :closed_at
    remove_column :booking_folios, :opened_at
    remove_column :booking_folios, :currency
    remove_column :booking_folios, :is_primary
    remove_column :booking_folios, :payer_id
    remove_column :booking_folios, :payer_type
    remove_column :booking_folios, :folio_type
    remove_column :booking_folios, :name

    permissions = Permission.where(slug: FOLIO_WINDOW_PERMISSIONS.keys)
    RolePermission.where(permission: permissions).delete_all
    permissions.destroy_all
  end

  private

  def seed_permissions!
    permissions = FOLIO_WINDOW_PERMISSIONS.to_h do |slug, name|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = name }
      [ slug, permission ]
    end

    Role.where(slug: %w[hotel_owner general_manager]).find_each do |role|
      permissions.each_value do |permission|
        RolePermission.find_or_create_by!(role: role, permission: permission)
      end
    end
  end
end
