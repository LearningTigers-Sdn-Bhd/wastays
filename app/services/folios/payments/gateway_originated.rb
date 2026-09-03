# frozen_string_literal: true

module Folios
  module Payments
    # Tells whether a payment row came from an online gateway instead of hotel staff.
    #
    # Read the metadata, never the category. `category` says which instrument the
    # money arrived on, not which workflow posted it: a card terminal at the front
    # desk and an online gateway charge both carry `gateway_payment`. Only one of
    # them touches a cashier drawer.
    module GatewayOriginated
      module_function

      def call(transaction)
        return false unless transaction.payment?

        metadata = transaction.metadata.to_h.stringify_keys

        metadata["payment_source"] == "gateway" ||
          metadata["payment_transaction_id"].present? ||
          metadata["posting_source"] == "gateway_payment"
      end
    end
  end
end
