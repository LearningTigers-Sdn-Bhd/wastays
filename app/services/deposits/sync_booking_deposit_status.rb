# frozen_string_literal: true

module Deposits
  class SyncBookingDepositStatus
    def self.call(booking)
      return unless booking

      deposits = booking.deposits.kind_security.includes(:deposit_movements).to_a
      status = if deposits.any? { |deposit| deposit.status.in?(%w[pending held]) && deposit.available_amount.positive? }
        deposits.any? { |deposit| deposit.status == "pending" } ? "pending_at_hotel" : "held"
      elsif deposits.any? { |deposit| deposit.applied_amount.positive? }
        "collected"
      elsif deposits.any?
        "released"
      else
        "not_required"
      end
      booking.update!(deposit_status: status)
    end
  end
end
