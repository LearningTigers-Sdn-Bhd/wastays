# frozen_string_literal: true

# Housekeeping work was one table doing three jobs, told apart by reading the
# details a human typed. This gives each job a name of its own.
#
# What this deliberately does not do is link a turnover to the checkout request
# that preceded it. A room is turned over when the guest leaves, whether or not
# they ever told anybody they were leaving -- most walk to the desk and say so.
# The link would have to be invented for the majority of cases, and an invented
# parent is worse than no parent.
class SeparateHousekeepingWorkContexts < ActiveRecord::Migration[8.0]
  def up
    add_column :housekeeping_requests, :work_context, :string, null: false, default: "guest_request"
    add_index :housekeeping_requests, :work_context
    add_index :housekeeping_requests, [ :work_context, :status, :requested_at ],
              name: "idx_housekeeping_requests_context_status_requested"

    backfill_contexts
  end

  def down
    remove_index :housekeeping_requests, name: "idx_housekeeping_requests_context_status_requested"
    remove_index :housekeeping_requests, :work_context
    remove_column :housekeeping_requests, :work_context
  end

  private

  # Each row already says which job it is; this only writes down what it says.
  #
  # A checkout's cleaning names its checkout in metadata. Rows written before
  # that metadata existed say so only through their details, which is exactly
  # the string-reading this column exists to end -- so it is read once, here,
  # and never again.
  #
  # A task raised against a room rather than a stay carries no booking. Whatever
  # is left is a guest asking for something.
  def backfill_contexts
    execute <<~SQL.squish
      UPDATE housekeeping_requests
      SET work_context = CASE
        WHEN COALESCE(metadata->>'checkout_request_id', '') <> '' THEN 'checkout_turnover'
        WHEN TRIM(request_details) = 'Checkout Room Cleaning' THEN 'checkout_turnover'
        WHEN booking_id IS NULL THEN 'vacant_room_task'
        ELSE 'guest_request'
      END
    SQL
  end
end
