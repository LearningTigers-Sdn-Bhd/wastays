# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class DepositSettlementsController < BaseController
        include GroupLifecycleTargeting

        def show
          load_settlement
          return render :show, layout: false unless request.post?

          result = @operation == "apply" ? apply_deposit : return_deposit
          return render_error(result.error) unless result.success?

          complete_settlement
        rescue BatchTargetError => e
          render_error(e.message)
        end

        private

        def load_settlement
          @checkout_bookings = selected_checkout_bookings
          @deposit = current_hotel.deposits.includes(:deposit_movements, :booking, :group_booking).find(params[:deposit_id])
          raise ActiveRecord::RecordNotFound unless deposit_available_to_checkout?

          @operation = params[:operation].to_s
          allowed = @deposit.kind_security? ? %w[apply release] : %w[refund]
          raise ActiveRecord::RecordNotFound unless @operation.in?(allowed)

          @eligible_folios = eligible_folios
          if @operation == "apply"
            Financials::EnsureDefaultTransactionCodes.call(current_hotel)
            @reason_codes = current_hotel.transaction_codes.active.charge
              .where(system_key: Deposits::Deduct::ALLOWED_REASON_KEYS).order(:name, :code).to_a
          else
            @reason_codes = []
          end
        end

        def selected_checkout_bookings
          ids = Array(params[:booking_ids]).reject(&:blank?).map(&:to_i).uniq
          return [ @booking ] if @booking.group_booking_id.blank?
          return [ @booking ] if ids.empty?

          bookings = @booking.group_booking.bookings.where(id: ids).order(:group_position, :id).to_a
          raise BatchTargetError, "One or more selected bookings are not part of this group." unless bookings.size == ids.size

          bookings
        end

        def deposit_available_to_checkout?
          return @checkout_bookings.map(&:id).include?(@deposit.booking_id) if @deposit.booking_id.present?

          @booking.group_booking_id.present? && @deposit.group_booking_id == @booking.group_booking_id
        end

        def eligible_folios
          scope = current_hotel.booking_folios.open.includes(:booking).where(
            booking_id: @checkout_bookings.map(&:id),
            currency: @deposit.currency
          )
          scope.select { |folio| @deposit.eligible_folio?(folio) }
        end

        def apply_deposit
          folio = @eligible_folios.find { |candidate| candidate.id == settlement_params[:booking_folio_id].to_i }
          return Deposits::Deduct::Result.failure("Select an eligible folio.", charge_transactions: [], movements: []) unless folio

          code = @reason_codes.find { |candidate| candidate.id == settlement_params[:transaction_code_id].to_i }
          Deposits::Deduct.call(
            deposit: @deposit,
            booking_folio: folio,
            amount: settlement_params[:amount],
            transaction_code: code,
            actor: current_user,
            posting_date: current_hotel.current_business_date,
            details: settlement_params[:details],
            operation_key: settlement_params[:operation_key]
          )
        end

        def return_deposit
          Deposits::Return.call(
            deposit: @deposit,
            amount: settlement_params[:amount],
            actor: current_user,
            payment_method: settlement_params[:payment_method],
            external_reference: settlement_params[:external_reference],
            reason: settlement_params[:reason],
            operation_key: settlement_params[:operation_key]
          )
        end

        def settlement_params
          @settlement_params ||= params.fetch(:deposit_settlement, {}).permit(
            :booking_folio_id, :transaction_code_id, :amount, :details, :payment_method,
            :external_reference, :reason, :operation_key
          )
        end

        def complete_settlement
          respond_to do |format|
            format.turbo_stream do
              render body: helpers.turbo_stream_action_tag(:complete_sheet, target: requesting_sheet_frame), content_type: Mime[:turbo_stream]
            end
            format.html { redirect_to @return_to, notice: "Deposit settlement recorded.", status: :see_other }
          end
        end

        def render_error(error)
          @settlement_error = error
          render :show, layout: false, status: :unprocessable_content
        end

        def requesting_sheet_frame
          turbo_frame_request_id.presence || "booking_action_sheet_secondary"
        end
      end
    end
  end
end
