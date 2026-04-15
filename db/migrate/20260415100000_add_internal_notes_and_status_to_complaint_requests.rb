class AddInternalNotesAndStatusToComplaintRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :housekeeping_requests, :internal_notes, :jsonb, default: [] unless column_exists?(:housekeeping_requests, :internal_notes)
    add_column :complaint_requests, :internal_notes, :jsonb, default: [] unless column_exists?(:complaint_requests, :internal_notes)
  end
end
