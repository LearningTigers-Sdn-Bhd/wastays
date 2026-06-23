class AddAgentAccountIdToBookingQuotes < ActiveRecord::Migration[8.0]
  def change
    add_reference :booking_quotes, :agent_account, null: true, foreign_key: true
  end
end
