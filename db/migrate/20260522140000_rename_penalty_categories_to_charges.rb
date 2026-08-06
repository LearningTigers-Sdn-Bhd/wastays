# frozen_string_literal: true

class RenamePenaltyCategoriesToCharges < ActiveRecord::Migration[7.1]
  def up
    FolioTransaction.where(category: "no_show_penalty").update_all(category: "no_show_charge")
    FolioTransaction.where(category: "late_checkout_penalty").update_all(category: "late_checkout_charge")
    FolioTransaction.where(category: "early_departure_penalty").update_all(category: "early_departure_charge")
  end

  def down
    FolioTransaction.where(category: "no_show_charge").update_all(category: "no_show_penalty")
    FolioTransaction.where(category: "late_checkout_charge").update_all(category: "late_checkout_penalty")
    FolioTransaction.where(category: "early_departure_charge").update_all(category: "early_departure_penalty")
  end
end
