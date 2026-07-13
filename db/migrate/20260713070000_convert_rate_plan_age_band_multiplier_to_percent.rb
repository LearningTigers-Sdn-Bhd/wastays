# frozen_string_literal: true

# Age band "multiplier" mode was stored as a fraction (0.4 = 40%), which is
# an unintuitive input for hoteliers who think in round percentages. Convert
# to a whole-percent value (40 = 40%) to match how RoomTypeRatePlan and
# ChannelDerivedSetting already represent their own multiplier adjustments.
class ConvertRatePlanAgeBandMultiplierToPercent < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE rate_plan_age_bands SET price_value = price_value * 100 WHERE pricing_mode = 'multiplier'
    SQL
    change_column_default :rate_plan_age_bands, :price_value, from: "1.0", to: "100.0"
  end

  def down
    execute <<~SQL.squish
      UPDATE rate_plan_age_bands SET price_value = price_value / 100 WHERE pricing_mode = 'multiplier'
    SQL
    change_column_default :rate_plan_age_bands, :price_value, from: "100.0", to: "1.0"
  end
end
