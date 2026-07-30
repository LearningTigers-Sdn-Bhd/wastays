# frozen_string_literal: true

# A CheckOutRequest was the only one of the three request tables with no record
# of when it finished, so everything reading the requests board had to stand
# `updated_at` in for it. That is not the same thing: updated_at moves on any
# write, so a completed checkout touched for any reason changed its place in the
# "Recently Completed" column -- which the column is now read through, a page at
# a time, and a row that moves is a row a reader sees twice or not at all.
#
# Backfilled from updated_at because that is precisely what the column has been
# showing as the finish time until now; no history is reinterpreted.
class AddCompletedAtToCheckOutRequests < ActiveRecord::Migration[8.0]
  def up
    add_column :check_out_requests, :completed_at, :datetime
    add_index :check_out_requests, [ :booking_id, :completed_at ]

    execute <<~SQL.squish
      UPDATE check_out_requests
         SET completed_at = updated_at
       WHERE status = 'completed'
         AND completed_at IS NULL
    SQL
  end

  def down
    remove_index :check_out_requests, [ :booking_id, :completed_at ]
    remove_column :check_out_requests, :completed_at
  end
end
