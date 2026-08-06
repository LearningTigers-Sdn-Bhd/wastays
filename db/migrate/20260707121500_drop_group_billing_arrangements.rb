# frozen_string_literal: true

class DropGroupBillingArrangements < ActiveRecord::Migration[7.1]
  def change
    # Remove foreign keys first to prevent constraint violations
    if foreign_key_exists?(:booking_billing_assignments, :group_billing_arrangements)
      remove_foreign_key :booking_billing_assignments, :group_billing_arrangements
    end
    if foreign_key_exists?(:booking_billing_assignments, :bookings)
      remove_foreign_key :booking_billing_assignments, :bookings
    end
    if foreign_key_exists?(:folio_routing_rules, :booking_billing_assignments)
      remove_foreign_key :folio_routing_rules, :booking_billing_assignments
    end
    if foreign_key_exists?(:folio_routing_rules, :group_billing_arrangements)
      remove_foreign_key :folio_routing_rules, :group_billing_arrangements
    end
    if foreign_key_exists?(:group_billing_arrangements, :group_bookings)
      remove_foreign_key :group_billing_arrangements, :group_bookings
    end
    if foreign_key_exists?(:group_billing_arrangements, :hotel_corporate_accounts)
      remove_foreign_key :group_billing_arrangements, :hotel_corporate_accounts
    end
    if foreign_key_exists?(:group_billing_arrangements, :hotels)
      remove_foreign_key :group_billing_arrangements, :hotels
    end

    # Remove columns and indexes from folio_routing_rules
    if column_exists?(:folio_routing_rules, :group_billing_arrangement_id)
      remove_column :folio_routing_rules, :group_billing_arrangement_id, :bigint
    end
    if column_exists?(:folio_routing_rules, :booking_billing_assignment_id)
      remove_column :folio_routing_rules, :booking_billing_assignment_id, :bigint
    end

    # Drop the tables
    drop_table :booking_billing_assignments, if_exists: true
    drop_table :group_billing_arrangements, if_exists: true
  end
end
