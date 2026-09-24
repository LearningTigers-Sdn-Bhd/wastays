# frozen_string_literal: true

# Two changes to how an agency's bookings are held for payment.
#
# 1. Whether an account may book at all is now an explicit permission rather
#    than something every linked account has by virtue of being linked. The hold
#    only means anything for an account that can actually take rooms, so the
#    permission gates the setting.
#
# 2. The property default moves from 48 hours to 72. Two days was never long
#    enough for an agency that transfers on a weekly cycle, and the extra day is
#    what the desks asked for.
class AddAgentBookingEnabledAndRaisePaymentHoldDefault < ActiveRecord::Migration[8.1]
  def up
    # Default false: booking on a client's behalf is granted, not assumed. The
    # invitation proposes it and the relationship form can revoke it.
    add_column :hotel_corporate_accounts, :agent_booking_enabled, :boolean,
               default: false, null: false

    change_column_default :hotels, :agent_payment_hold_hours, from: 48, to: 72

    # Only the properties still sitting on the old default. A hotel that typed
    # its own hold chose that number, and this is not the migration to overrule
    # it.
    execute <<~SQL.squish
      UPDATE hotels SET agent_payment_hold_hours = 72 WHERE agent_payment_hold_hours = 48
    SQL
  end

  def down
    change_column_default :hotels, :agent_payment_hold_hours, from: 72, to: 48
    remove_column :hotel_corporate_accounts, :agent_booking_enabled
  end
end
