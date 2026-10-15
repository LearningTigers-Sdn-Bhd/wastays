# frozen_string_literal: true

# Which travel agencies may book a rate plan through the corporate portal.
#
#   hidden -- no agency sees it
#   all    -- every linked agency sees it
#   except -- every agency but the ones listed in rate_plan_agency_rules
#   only   -- only the agencies listed in rate_plan_agency_rules
#
# Until now the portal offered one plan per room category: the Corporate Rate,
# or Standard where the category had no active Corporate plan. The backfill
# reproduces exactly that, so agents see nothing new on deploy.
class AddTaAccessToRatePlans < ActiveRecord::Migration[8.1]
  def up
    add_column :rate_plans, :ta_access, :string, default: "hidden", null: false
    add_check_constraint :rate_plans, "ta_access IN ('hidden', 'all', 'except', 'only')", name: "rate_plans_ta_access_check"

    create_table :rate_plan_agency_rules do |t|
      t.references :rate_plan, null: false, foreign_key: true, index: false
      t.references :hotel_corporate_account, null: false, foreign_key: true
      t.timestamps
    end
    add_index :rate_plan_agency_rules, %i[rate_plan_id hotel_corporate_account_id], unique: true, name: "idx_rate_plan_agency_rules_unique"

    execute <<~SQL.squish
      UPDATE rate_plans SET ta_access = 'all' WHERE kind = 'corporate'
    SQL
    execute <<~SQL.squish
      UPDATE rate_plans standard SET ta_access = 'all'
      WHERE standard.kind = 'standard'
        AND NOT EXISTS (
          SELECT 1
          FROM room_type_rate_plans own
          JOIN room_type_rate_plans sibling ON sibling.room_type_id = own.room_type_id
          JOIN rate_plans corporate ON corporate.id = sibling.rate_plan_id
          WHERE own.rate_plan_id = standard.id
            AND corporate.kind = 'corporate'
            AND corporate.archived_at IS NULL
        )
    SQL
  end

  def down
    drop_table :rate_plan_agency_rules
    remove_check_constraint :rate_plans, name: "rate_plans_ta_access_check"
    remove_column :rate_plans, :ta_access
  end
end
