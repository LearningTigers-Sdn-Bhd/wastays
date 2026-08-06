class AddProfessionalFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :internal_notes, :text
    add_column :bookings, :manual_rate_override, :decimal
  end
end
