# frozen_string_literal: true

# What a child of a given age pays, for one room category on one rate plan.
#
# The age bands themselves stay on the rate plan — they are the property's one
# definition of who counts as a child. Only the money moves here, because a
# child in a suite and a child in a single are not worth the same to the room.
#
# Deliberately the same shape as room_type_rate_plan_occupancy_prices, which
# already answers "what does this pairing charge for N adults".
class CreateRoomTypeRatePlanAgeBandPrices < ActiveRecord::Migration[8.0]
  def up
    create_table :room_type_rate_plan_age_band_prices do |t|
      t.references :room_type_rate_plan, null: false, foreign_key: true
      t.references :rate_plan_age_band, null: false, foreign_key: true
      t.decimal :price, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :room_type_rate_plan_age_band_prices,
              %i[room_type_rate_plan_id rate_plan_age_band_id],
              unique: true,
              name: "idx_rtrp_age_band_prices_unique"

    # A legacy flat amount has the same meaning for every room assignment and
    # can be copied safely. Percentages remain on the band because converting a
    # percentage without a nightly adult-rate anchor would change its meaning.
    execute <<~SQL.squish
      INSERT INTO room_type_rate_plan_age_band_prices
        (room_type_rate_plan_id, rate_plan_age_band_id, price, created_at, updated_at)
      SELECT room_type_rate_plans.id, rate_plan_age_bands.id,
             rate_plan_age_bands.price_value, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM room_type_rate_plans
      INNER JOIN rate_plan_age_bands
        ON rate_plan_age_bands.rate_plan_id = room_type_rate_plans.rate_plan_id
      WHERE rate_plan_age_bands.pricing_mode = 'amount'
      ON CONFLICT (room_type_rate_plan_id, rate_plan_age_band_id) DO NOTHING
    SQL
  end

  def down
    drop_table :room_type_rate_plan_age_band_prices
  end
end
