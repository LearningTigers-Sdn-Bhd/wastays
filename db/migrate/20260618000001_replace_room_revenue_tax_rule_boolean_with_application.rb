# frozen_string_literal: true

class ReplaceRoomRevenueTaxRuleBooleanWithApplication < ActiveRecord::Migration[8.0]
  def change
    remove_column :hotel_transaction_configurations,
      :apply_room_revenue_tax_rules_to_new_bookings,
      :boolean,
      null: false,
      default: false

    add_column :hotel_transaction_configurations,
      :room_revenue_tax_rule_application,
      :string,
      null: false,
      default: "new_bookings_only"
  end
end
