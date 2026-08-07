# frozen_string_literal: true

# How a property sells — by the room or by the guest — used to be spread across
# three columns: an admin entitlement (`allow_pax_pricing`), an owner opt-in
# (`pax_pricing_only`) and a per-plan `rate_plans.sell_mode` that staff picked
# in the rate plan sheet. Three fields for one structural decision, kept in
# agreement only by validations.
#
# The property now decides once, and every rate plan mirrors it. `sell_mode`
# deliberately reuses the `rate_plans.sell_mode` vocabulary so the mirror is a
# literal copy with no translation layer.
class AddSellModeToHotels < ActiveRecord::Migration[8.0]
  def up
    add_column :hotels, :sell_mode, :string, default: "per_room", null: false

    execute <<~SQL.squish
      UPDATE hotels SET sell_mode = 'per_person' WHERE pax_pricing_only = TRUE
    SQL

    # Pax hotels previously kept their Standard and special-tier plans on
    # per_room, exempted by RatePlan#sell_mode_matches_hotel_exclusivity. That
    # exemption is gone, so bring those rows in line with their hotel.
    execute <<~SQL.squish
      UPDATE rate_plans SET sell_mode = 'per_person'
      WHERE hotel_id IN (SELECT id FROM hotels WHERE sell_mode = 'per_person')
    SQL

    remove_column :hotels, :pax_pricing_only
    remove_column :hotels, :allow_pax_pricing
  end

  def down
    add_column :hotels, :pax_pricing_only, :boolean, default: false, null: false
    add_column :hotels, :allow_pax_pricing, :boolean, default: false, null: false

    execute <<~SQL.squish
      UPDATE hotels SET pax_pricing_only = TRUE, allow_pax_pricing = TRUE
      WHERE sell_mode = 'per_person'
    SQL

    remove_column :hotels, :sell_mode
  end
end
