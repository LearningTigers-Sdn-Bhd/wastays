module NightAudits
  module Evaluation
    class FolioState
      def outstanding_balance(folio)
        folio.folio_transactions.to_a.sum do |transaction|
          case transaction.transaction_type
          when "payment" then -transaction.amount.to_d
          else transaction.amount.to_d
          end
        end
      end

      def payment_synced?(folio, payment_transaction)
        expected_amount = payment_transaction.amount_subunits.to_d / 100.0

        folio.folio_transactions.any? do |transaction|
          transaction.transaction_type == "payment" &&
            transaction.metadata["payment_transaction_id"].to_s == payment_transaction.id.to_s &&
            transaction.amount.to_d == expected_amount
        end
      end

      def refund_synced?(folio, refund_request)
        expected_amount = -refund_request.refund_amount.to_d

        folio.folio_transactions.any? do |transaction|
          transaction.transaction_type == "payment" &&
            transaction.metadata["refund_request_id"].to_s == refund_request.id.to_s &&
            transaction.amount.to_d == expected_amount
        end
      end
    end
  end
end
