# frozen_string_literal: true

class AddHidePayoutReportsToHotels < ActiveRecord::Migration[8.1]
  def change
    add_column :hotels, :hide_payout_reports, :boolean, default: false, null: false
  end
end
