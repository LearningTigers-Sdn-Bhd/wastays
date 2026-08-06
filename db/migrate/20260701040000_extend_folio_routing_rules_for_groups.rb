# frozen_string_literal: true

class ExtendFolioRoutingRulesForGroups < ActiveRecord::Migration[8.0]
  def change
    add_reference :folio_routing_rules, :group_billing_arrangement, null: true, foreign_key: true
    add_reference :folio_routing_rules, :booking_billing_assignment, null: true, foreign_key: true
    add_column :folio_routing_rules, :source_type, :string, null: false, default: "booking"
    add_column :folio_routing_rules, :effective_from, :date
    add_column :folio_routing_rules, :effective_until, :date
    add_column :folio_routing_rules, :coverage_percentage, :decimal, precision: 5, scale: 2, null: false, default: 100

    add_check_constraint :folio_routing_rules,
      "source_type IN ('booking', 'group')",
      name: "folio_routing_rules_source_allowed"
    add_check_constraint :folio_routing_rules,
      "coverage_percentage > 0 AND coverage_percentage <= 100",
      name: "folio_routing_rules_coverage_percentage"
  end
end
