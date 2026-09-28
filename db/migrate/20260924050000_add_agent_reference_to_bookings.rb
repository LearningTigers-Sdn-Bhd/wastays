# frozen_string_literal: true

# The travel agency's own number for a booking (their voucher or file
# reference). Agencies reconcile by it, so it is searchable alongside the
# hotel's own reservation number.
class AddAgentReferenceToBookings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :bookings, :agent_reference, :string
    add_index :bookings, %i[hotel_id agent_reference], where: "agent_reference IS NOT NULL",
      algorithm: :concurrently, name: "idx_bookings_on_hotel_agent_reference"
  end
end
