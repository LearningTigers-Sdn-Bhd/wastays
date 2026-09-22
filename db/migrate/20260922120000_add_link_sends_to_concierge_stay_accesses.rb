class AddLinkSendsToConciergeStayAccesses < ActiveRecord::Migration[8.0]
  def change
    # A guest can ask for the stay link again after a lock. The cap stops a
    # stranger with the URL from mailing the guest without end.
    add_column :concierge_stay_accesses, :send_count, :integer, null: false, default: 0
    add_column :concierge_stay_accesses, :send_window_started_at, :datetime
    add_column :concierge_stay_accesses, :link_sent_at, :datetime
  end
end
