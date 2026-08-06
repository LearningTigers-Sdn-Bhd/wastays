# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "split transaction". Splits part of a posted charge onto
      # another open folio window, by amount or by percent.
      #
      # Business rules live in Folios::Transactions::SplitTransaction; this
      # controller only orchestrates authorization, input, rendering, and
      # completion. The service enforces the same permission — the controller
      # gate here makes GET and POST symmetric rather than replacing it.
      class TransactionSplitsController < BaseController
        def show
          return create if request.post?

          load_transaction
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_movements")
        end

        def load_transaction
          @transaction = booking_transaction_scope.includes(:transaction_code).find(params[:transaction_id])
          @source_folio = @transaction.booking_folio
          @target_folios = @booking.booking_folios.open
                                   .order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc)
                                   .reject { |folio| folio.id == @source_folio.id }
        end

        def create
          transaction = booking_transaction_scope.find(params[:transaction_id])
          target_folio = @booking.booking_folios.find(folio_operation_params[:target_folio_id])

          result = ::Folios::Transactions::SplitTransaction.call(
            transaction: transaction,
            target_folio: target_folio,
            user: current_user,
            reason: folio_operation_params[:reason],
            amount: folio_operation_params[:amount],
            percent: folio_operation_params[:percent],
            posting_date: current_hotel.current_business_date
          )

          return complete_action(alert: result.error) unless result.success?

          complete_action(notice: "Folio transaction split.")
        end

        def booking_transaction_scope
          FolioTransaction.joins(:booking_folio)
                          .where(booking_folios: { booking_id: @booking.id, hotel_id: current_hotel.id })
        end

        def folio_operation_params
          params.require(:folio_operation).permit(:target_folio_id, :reason, :amount, :percent)
        end
      end
    end
  end
end
