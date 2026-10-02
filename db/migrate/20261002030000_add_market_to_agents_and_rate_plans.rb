# frozen_string_literal: true

# Travel agents are local or international, and a hotel prices them differently.
# `market` marks the agent on its relationship with the hotel (nil = not set yet),
# and `ta_market` says which agents a rate plan is offered to. A plan marked for
# one market is hidden from the other, and from agents with no market set.
class AddMarketToAgentsAndRatePlans < ActiveRecord::Migration[8.1]
  def change
    add_column :hotel_corporate_accounts, :market, :string
    add_check_constraint :hotel_corporate_accounts, "market IS NULL OR market IN ('local', 'international')",
                         name: "hotel_corporate_accounts_market_check"

    add_column :rate_plans, :ta_market, :string, null: false, default: "all"
    add_check_constraint :rate_plans, "ta_market IN ('all', 'local', 'international')",
                         name: "rate_plans_ta_market_check"
  end
end
