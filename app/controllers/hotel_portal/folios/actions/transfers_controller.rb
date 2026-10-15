# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      class TransfersController < BaseController
        def show
          prepare_form
          if request.post?
            if params[:workflow_step] == "apply"
              result = ::Folios::TransferFolios.call(**transfer_attributes, preview_token: params[:preview_token])
              return complete_action(notice: "Folio transfer completed.") if result.success?

              flash.now[:alert] = result.error
            elsif params[:workflow_step] == "edit"
              @preview = nil
            elsif params[:workflow_step] == "preview"
              @preview = ::Folios::TransferFolios.preview(**transfer_attributes)
              flash.now[:alert] = @preview.error unless @preview.success?
            else
              flash.now[:alert] = "Select a valid transfer action."
            end
          end
          @entry_presenter = TransferPresenter.new(rows: @preview&.success? ? @preview.rows : @rows)
          render :show, formats: [ :html ], layout: false, status: flash.now[:alert].present? ? :unprocessable_content : :ok
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_movements")
        end

        def prepare_form
          @draft = params.fetch(:folio_transfer, {}).permit(:target_folio_id, :reason, :idempotency_key,
            source_folio_ids: [], transaction_ids: [], route_code_ids: []).to_h if params[:folio_transfer]
          @draft ||= {}
          @draft["idempotency_key"] ||= SecureRandom.uuid
          @draft["source_folio_ids"] ||= [ params[:active_folio_id].presence || @booking.booking_folio&.id ].compact.map(&:to_s)
          @folios = ::Folios::DestinationPolicy.folios(booking: @booking).open.to_a
          @rows = FolioTransaction.where(booking_folio_id: @folios.map(&:id))
            .includes(:transaction_code, :deposit_movement, :source_booking, booking_folio: :booking)
            .where(voided_by_transaction_id: nil, reversal_of_transaction_id: nil).order(:posting_date, :id).to_a
          @row_errors = @rows.to_h { |row| [ row.id, ::Folios::Transactions::MovementPolicy.error(row) ] }
          @draft["transaction_ids"] ||= @rows.select { |row| row.charge? && @row_errors[row.id].nil? && @draft["source_folio_ids"].include?(row.booking_folio_id.to_s) }.map { |row| row.id.to_s }
          @codes = ::Folios::Routing::RoutabilityPolicy.parent_codes(hotel: current_hotel).to_a
        end

        def transfer_attributes
          { booking: @booking, actor: current_user, source_folio_ids: @draft["source_folio_ids"],
            transaction_ids: @draft["transaction_ids"], target_folio_id: @draft["target_folio_id"],
            reason: @draft["reason"], idempotency_key: @draft["idempotency_key"], route_code_ids: @draft["route_code_ids"] }
        end
      end
    end
  end
end
