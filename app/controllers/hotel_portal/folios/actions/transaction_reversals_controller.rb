# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "reverse transaction". Posts an immutable correction row
      # with the opposite amount.
      #
      # Business rules live in Folios::Transactions::ReverseTransaction; this
      # controller only orchestrates authorization, input, rendering, and
      # completion.
      class TransactionReversalsController < BaseController
        def show
          return create if request.post?

          load_transaction
          render :show, layout: false
        end

        private

        # The only folio action that does not use the authorize hook.
        # TransactionActionPolicy#reverse_allowed? answers one question over a
        # list that mixes authorization ("you lack post_folio_corrections") with
        # business state ("night audit row", "already reversed", "gateway
        # payments use the refund workflow"). Raising Pundit::NotAuthorizedError
        # would turn every one of those explanations into a bare redirect, so
        # the check stays in the action body and reports its own reason.
        def authorize_folio_action!; end

        def load_transaction
          @transaction = booking_transaction_scope.includes(:transaction_code).find(params[:transaction_id])
          @policy = reversal_policy(@transaction)
          @blocked_reason = @policy.reverse_error unless @policy.reverse_allowed?
        end

        def create
          transaction = booking_transaction_scope.find(params[:transaction_id])
          policy = reversal_policy(transaction)
          return complete_action(alert: policy.reverse_error) unless policy.reverse_allowed?

          result = ::Folios::Transactions::ReverseTransaction.call(
            transaction: transaction,
            user: current_user,
            correction_reason: reversal_params[:correction_reason],
            correction_note: reversal_params[:correction_note],
            posting_date: current_hotel.current_business_date
          )

          return complete_action(alert: result.error) unless result.success?

          complete_action(notice: "Folio transaction reversed.")
        end

        def reversal_policy(transaction)
          ::Folios::Transactions::TransactionActionPolicy.new(
            transaction: transaction,
            user: current_user,
            posting_date: current_hotel.current_business_date
          )
        end

        def booking_transaction_scope
          FolioTransaction.joins(:booking_folio)
                          .where(booking_folios: { booking_id: @booking.id, hotel_id: current_hotel.id })
        end

        def reversal_params
          params.require(:folio_transaction).permit(:correction_reason, :correction_note)
        end
      end
    end
  end
end
