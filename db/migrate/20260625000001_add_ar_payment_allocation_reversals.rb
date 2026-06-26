# frozen_string_literal: true

class AddArPaymentAllocationReversals < ActiveRecord::Migration[8.0]
  PERMISSION_SLUG = "manage_ar_payments"
  ROLE_SLUGS = %w[hotel_owner general_manager].freeze

  def up
    remove_index :ar_payment_allocations, name: "idx_ar_allocations_unique_payment_invoice"
    add_index :ar_payment_allocations, [ :ar_payment_id, :ar_invoice_id ], name: "idx_ar_allocations_on_payment_invoice"

    create_table :ar_payment_allocation_reversals do |t|
      t.references :ar_payment_allocation, null: false, foreign_key: true, index: { unique: true, name: "idx_ar_allocation_reversals_unique" }
      t.references :reversed_by, null: false, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.datetime :reversed_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    permission = Permission.find_or_create_by!(slug: PERMISSION_SLUG) do |record|
      record.name = "Manage AR Payments"
    end

    Role.where(slug: ROLE_SLUGS).find_each do |role|
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
  end

  def down
    permission = Permission.find_by(slug: PERMISSION_SLUG)
    if permission
      RolePermission.where(permission: permission).delete_all
      permission.destroy!
    end

    drop_table :ar_payment_allocation_reversals
    remove_index :ar_payment_allocations, name: "idx_ar_allocations_on_payment_invoice"
    add_index :ar_payment_allocations, [ :ar_payment_id, :ar_invoice_id ], unique: true, name: "idx_ar_allocations_unique_payment_invoice"
  end
end
