# frozen_string_literal: true

# How long an agent's booking is held before payment, and when this one falls
# due.
#
# Deliberately NOT hotel_corporate_accounts.payment_terms_days: that is when an
# AR invoice falls due, and sharing it would make an invoice-terms change
# silently release inventory.
#
# `payment_due_at` is wall-clock, not the hotel's business date. The business
# date only moves when the night audit runs and can sit days behind; a deadline
# is a promise made to an agent about real time.
class AddAgentPaymentHoldToBookingsAndAccounts < ActiveRecord::Migration[8.1]
  def change
    # The property's default, in hours. 48 matches the hold agents are used to.
    add_column :hotels, :agent_payment_hold_hours, :integer, default: 48, null: false

    # Per-agency override; null means "use the hotel's default".
    add_column :hotel_corporate_accounts, :agent_payment_hold_hours, :integer, null: true

    add_column :bookings, :payment_due_at, :datetime, null: true
    # The sweeper reads exactly this: what is overdue and not yet cancelled.
    add_index :bookings, [ :payment_due_at, :status ],
              where: "payment_due_at IS NOT NULL",
              name: "index_bookings_on_payment_due_at_and_status"

    add_check_constraint :hotels, "agent_payment_hold_hours > 0",
                         name: "hotels_agent_payment_hold_hours_positive"
    add_check_constraint :hotel_corporate_accounts,
                         "agent_payment_hold_hours IS NULL OR agent_payment_hold_hours > 0",
                         name: "hotel_corporate_accounts_agent_payment_hold_hours_positive"
  end
end
