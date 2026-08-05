# frozen_string_literal: true

# Rate plan identity used to be derived by string-matching `name`, so renaming a
# plan silently changed whether it was deletable, archivable, and exempt from the
# pax-exclusivity rule. This stores the identity instead.
#
# The backfill reproduces the old matcher exactly (RatePlan#special_tier_kind and
# #standard_rate? as of this migration), so no plan changes class on deploy. Any
# name the matcher did not recognise was already treated as an ordinary plan and
# becomes "custom".
class AddKindToRatePlans < ActiveRecord::Migration[8.0]
  KIND_BY_NORMALIZED_NAME = {
    "standard" => [ "standard rate" ],
    "walk_in" => [ "walk-in rate", "walk in rate", "walk-in", "walk in" ],
    "corporate" => [ "corporate rate", "corporate" ],
    "ota" => [ "ota rate", "ota" ]
  }.freeze

  def up
    add_column :rate_plans, :kind, :string, null: false, default: "custom"
    backfill_kinds
  end

  def down
    remove_column :rate_plans, :kind
  end

  private

  def backfill_kinds
    KIND_BY_NORMALIZED_NAME.each do |kind, names|
      execute <<~SQL.squish
        UPDATE rate_plans
        SET kind = #{quote(kind)}
        WHERE lower(btrim(name)) IN (#{names.map { |name| quote(name) }.join(', ')})
      SQL
    end
  end

  def quote(value) = connection.quote(value)
end
