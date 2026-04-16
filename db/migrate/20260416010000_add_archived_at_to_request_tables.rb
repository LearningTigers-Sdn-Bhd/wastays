class AddArchivedAtToRequestTables < ActiveRecord::Migration[8.0]
  def change
    add_column :housekeeping_requests, :archived_at, :datetime unless column_exists?(:housekeeping_requests, :archived_at)
    add_column :complaint_requests, :archived_at, :datetime unless column_exists?(:complaint_requests, :archived_at)

    add_index :housekeeping_requests, [ :booking_id, :archived_at ] unless index_exists?(:housekeeping_requests, [ :booking_id, :archived_at ])
    add_index :complaint_requests, [ :booking_id, :archived_at ] unless index_exists?(:complaint_requests, [ :booking_id, :archived_at ])
  end
end
