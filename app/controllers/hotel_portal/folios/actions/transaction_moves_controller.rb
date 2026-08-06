# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "move transaction". Renders the target-folio form (GET) and
      # performs the move (POST), including per-tax routing overrides.
      #
      # Business rules live in Folios::Transactions::MoveTransaction; this
      # controller only orchestrates authorization, input, rendering, and
      # completion. The service enforces the same permission — the controller
      # gate here makes GET and POST symmetric rather than replacing it.
      class TransactionMovesController < BaseController
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
          @open_folios = @booking.booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc).to_a
          @target_folios = @open_folios.reject { |folio| folio.id == @source_folio.id }
          @tax_transactions = ::Folios::Transactions::AttachedTaxTransactions.call(@transaction)
        end

        def create
          transaction = booking_transaction_scope.find(params[:transaction_id])
          target_folio = @booking.booking_folios.find(folio_operation_params[:target_folio_id])

          result = ::Folios::Transactions::MoveTransaction.call(
            transaction: transaction,
            target_folio: target_folio,
            user: current_user,
            reason: folio_operation_params[:reason],
            posting_date: current_hotel.current_business_date,
            tax_routes: tax_route_params
          )

          return complete_action(alert: result.error) unless result.success?

          complete_action(notice: "Folio transaction moved.")
        end

        def booking_transaction_scope
          FolioTransaction.joins(:booking_folio)
                          .where(booking_folios: { booking_id: @booking.id, hotel_id: current_hotel.id })
        end

        def folio_operation_params
          params.require(:folio_operation).permit(:target_folio_id, :reason, tax_routes: [ :transaction_id, :target_folio_id ])
        end

        def tax_route_params
          folio_operation_params[:tax_routes].to_h.values.each_with_object({}) do |attributes, routes|
            attributes = attributes.to_h.with_indifferent_access
            transaction_id = attributes[:transaction_id].presence
            next if transaction_id.blank?

            routes[transaction_id.to_s] = attributes[:target_folio_id].presence
          end
        end
      end
    end
  end
end
