# frozen_string_literal: true

class ConstrainBookingFolioStatuses < ActiveRecord::Migration[8.0]
  CONSTRAINT_NAME = "booking_folios_status_allowed"

  def up
    add_check_constraint :booking_folios,
      "status IN ('open', 'closed')",
      name: CONSTRAINT_NAME
  end

  def down
    remove_check_constraint :booking_folios, name: CONSTRAINT_NAME
  end
end
