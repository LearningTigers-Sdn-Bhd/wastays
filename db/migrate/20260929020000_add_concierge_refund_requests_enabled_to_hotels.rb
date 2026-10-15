class AddConciergeRefundRequestsEnabledToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :concierge_refund_requests_enabled, :boolean, default: false, null: false
  end
end
