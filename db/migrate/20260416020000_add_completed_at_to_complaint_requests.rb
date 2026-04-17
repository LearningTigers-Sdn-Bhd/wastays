class AddCompletedAtToComplaintRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :complaint_requests, :completed_at, :datetime unless column_exists?(:complaint_requests, :completed_at)
    add_index :complaint_requests, [ :booking_id, :completed_at ] unless index_exists?(:complaint_requests, [ :booking_id, :completed_at ])
  end
end
