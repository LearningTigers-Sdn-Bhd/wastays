# frozen_string_literal: true

# A booking cancelled today must be judged by the policy that was in force when it
# was booked — the same contract the tax snapshot already follows. The existing
# `cancellation_policy_snapshot` text column cannot carry a fee schedule, so this
# adds a structured payload beside it.
#
# The text columns stay for one release: readers fall back to them while old rows
# still carry prose. Dropping them is a later migration.
class AddCancellationPolicySnapshotData < ActiveRecord::Migration[8.0]
  class MigrationBooking < ActiveRecord::Base
    self.table_name = "bookings"
  end

  class MigrationBookingQuote < ActiveRecord::Base
    self.table_name = "booking_quotes"
  end

  def up
    add_column :bookings, :cancellation_policy_snapshot_data, :jsonb, null: false, default: {}
    add_column :booking_quotes, :cancellation_policy_snapshot_data, :jsonb, null: false, default: {}

    backfill(MigrationBooking)
    backfill(MigrationBookingQuote)

    drop_table :cancellation_policy_templates
  end

  def down
    create_table :cancellation_policy_templates do |t|
      t.string :name
      t.text :body
      t.timestamps
    end

    remove_column :booking_quotes, :cancellation_policy_snapshot_data
    remove_column :bookings, :cancellation_policy_snapshot_data
  end

  private

  # Prose is preserved verbatim under `legacy_text`; it is never parsed into tiers,
  # because a number guessed out of free text is exactly the drift this replaces.
  def backfill(model)
    model.where.not(cancellation_policy_snapshot: [ nil, "" ]).in_batches do |batch|
      batch.each do |record|
        record.update_columns(
          cancellation_policy_snapshot_data: { "legacy_text" => record.cancellation_policy_snapshot }
        )
      end
    end
  end
end
