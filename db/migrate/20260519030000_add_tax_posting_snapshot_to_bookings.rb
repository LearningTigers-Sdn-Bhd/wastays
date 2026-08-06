# frozen_string_literal: true

class AddTaxPostingSnapshotToBookings < ActiveRecord::Migration[7.1]
  def change
    add_column :bookings, :tax_posting_snapshot, :jsonb, default: {}, null: false
  end
end
