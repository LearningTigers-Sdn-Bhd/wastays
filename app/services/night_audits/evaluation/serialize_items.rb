module NightAudits
  module Evaluation
    class SerializeItems
      def bookings(scope, reason)
        ordered = if scope.respond_to?(:order)
          scope.order(:check_out, :id)
        else
          scope.sort_by { |booking| [ booking.check_out, booking.id ] }
        end

        ordered.map { |record| booking(record, reason) }
      end

      def booking(record, reason)
        {
          "booking_id" => record.id,
          "confirmation_token" => record.confirmation_token,
          "guest_name" => record.guest_name,
          "status" => record.status,
          "check_in" => record.check_in,
          "check_out" => record.check_out,
          "room_numbers" => record.room_numbers.presence,
          "reason" => reason
        }
      end

      def payment_transactions(records, reason)
        records.sort_by(&:id).map do |payment_transaction|
          booking = payment_transaction.booking

          {
            "payment_transaction_id" => payment_transaction.id,
            "booking_id" => booking.id,
            "confirmation_token" => booking.confirmation_token,
            "guest_name" => booking.guest_name,
            "amount" => payment_transaction.amount_subunits.to_d / 100.0,
            "gateway" => payment_transaction.gateway,
            "external_reference" => payment_transaction.external_reference,
            "reason" => reason
          }
        end
      end

      def refund_requests(records, reason)
        records.sort_by(&:id).map do |refund_request|
          booking = refund_request.booking

          {
            "refund_request_id" => refund_request.id,
            "booking_id" => booking.id,
            "confirmation_token" => booking.confirmation_token,
            "guest_name" => booking.guest_name,
            "amount" => refund_request.refund_amount,
            "reason" => reason
          }
        end
      end

      def requests(scope, details_method, reason)
        scope.order(:requested_at, :id).map do |request|
          booking = request.booking

          {
            "request_id" => request.id,
            "booking_id" => booking.id,
            "confirmation_token" => booking.confirmation_token,
            "guest_name" => booking.guest_name,
            "status" => request.status,
            "details" => request.public_send(details_method),
            "reason" => reason
          }
        end
      end
    end
  end
end
