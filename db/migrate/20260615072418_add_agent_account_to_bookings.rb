class AddAgentAccountToBookings < ActiveRecord::Migration[8.0]
  def change
    add_reference :bookings, :agent_account, null: true, foreign_key: true
  end
end
