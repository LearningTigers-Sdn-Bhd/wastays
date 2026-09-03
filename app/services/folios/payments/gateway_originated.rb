# frozen_string_literal: true

module Folios
  module Payments
    # Tells whether a payment row came from an online gateway instead of hotel staff.
    #
    # Read the metadata, never the category. `category` says which instrument the
    # money arrived on, not which workflow posted it: a card terminal at the front
    # desk and an online gateway charge both carry `gateway_payment`. Only one of
    # them touches a cashier drawer.
    #
    # `call` reads the metadata alone. `for` also consults the linked
    # PaymentTransaction, because a link is not proof of an online charge: manual
    # booking records one with `gateway: "manual"`, and staff handled that money
    # themselves. Use `for` wherever a wrong answer moves money between reports.
    class GatewayOriginated
      def self.call(transaction)
        new.call(transaction)
      end

      def self.for(transactions)
        new(direct_payment_ids: direct_payment_ids_for(transactions))
      end

      def self.direct_payment_ids_for(transactions)
        linked_ids = transactions.filter_map do |transaction|
          transaction.metadata.to_h.stringify_keys["payment_transaction_id"].presence
        end
        return Set.new if linked_ids.empty?

        PaymentTransaction
          .where(id: linked_ids)
          .where(gateway: "manual").or(PaymentTransaction.where(id: linked_ids, event_source: "manual_booking"))
          .pluck(:id)
          .map(&:to_s)
          .to_set
      end

      def initialize(direct_payment_ids: nil)
        @direct_payment_ids = direct_payment_ids
      end

      def call(transaction)
        return false unless transaction.payment?

        metadata = transaction.metadata.to_h.stringify_keys
        return true if metadata["payment_source"] == "gateway"

        linked_id = metadata["payment_transaction_id"].presence
        # The linked record is the authority when we have it. A staff-recorded
        # payment keeps its own posting metadata, so the fallback below would
        # otherwise call it a gateway charge.
        return !@direct_payment_ids.include?(linked_id.to_s) if linked_id && @direct_payment_ids

        linked_id.present? || metadata["posting_source"] == "gateway_payment"
      end
    end
  end
end
