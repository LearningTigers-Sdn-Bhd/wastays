# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module Bookings
    class WorkspaceActionsController < BaseController
    before_action :authorize_manage_bookings!
    before_action :set_booking

    def update_room_rate
      result = if room_rate_params[:room_number].present? && room_rate_params.except(:room_number, :override, :override_reason).empty?
        ::Bookings::AssignRoom.new(
          booking: @booking,
          room_number: room_rate_params[:room_number],
          user: current_user,
          override: room_rate_params[:override],
          override_reason: room_rate_params[:override_reason]
        ).call
      else
        ::Bookings::UpdateStayService.new(
          booking: @booking,
          params: room_rate_params.except(:override, :override_reason).to_h.symbolize_keys,
          user: current_user,
          override: room_rate_params[:override],
          override_reason: room_rate_params[:override_reason]
        ).call
      end
      redirect_with_result(result, tab: "room_and_rate")
    end

    def add_billing_party
      unless @booking.group_booking_id?
        result = ::BookingBillingParties::ManageCompany.call(
          booking: @booking, actor: current_user, attributes: billing_party_params
        )
        return redirect_with_result(result, tab: "billing_preferences",
          billing_editor: (result.success? ? "party" : nil), billing_party_id: result.party&.id)
      end

      if params[:scope].blank?
        prepare_confirm_group_scope
        return render "hotel_portal/bookings/workspaces/billing_preferences/confirm_group_scope"
      end

      result = if params[:scope] == "group"
        ::BookingBillingParties::ManageCompany.call_for_group(
          group_booking: group_booking, actor: current_user, attributes: billing_party_params
        )
      else
        ::BookingBillingParties::ManageCompany.call(
          booking: @booking, actor: current_user, attributes: billing_party_params
        )
      end

      if result.success?
        party = resolved_billing_party(result)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = "Billing party added."
            render turbo_stream: turbo_stream.update("offcanvas_drawer",
              partial: "hotel_portal/bookings/workspaces/billing_preferences/edit_terms_offcanvas_content",
              locals: { party: party })
          end
          format.html do
            redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "billing_preferences",
              billing_editor: "party", billing_party_id: party.id), notice: "Billing party added."
          end
        end
      else
        prepare_confirm_group_scope
        flash.now[:alert] = result.error
        render "hotel_portal/bookings/workspaces/billing_preferences/confirm_group_scope", status: :unprocessable_content
      end
    end

    def update_billing_terms
      party = @booking.booking_billing_parties.active.find(params[:billing_party_id])
      result = ::BookingBillingParties::UpdateTerms.call(
        party: party, actor: current_user, attributes: billing_terms_params
      )

      if result.success? && params[:offcanvas].present?
        destination = hotel_booking_workspace_path(current_hotel, @booking, tab: "billing_preferences", billing_party_id: party.id)
        return offcanvas_transaction_response(destination: destination, notice: "Billing terms saved.")
      end

      redirect_with_result(result, tab: "billing_preferences", billing_party_id: party.id)
    end

    def archive_billing_party
      party = @booking.booking_billing_parties.companies.active.find(params[:billing_party_id])
      result = if party.archiveable?
        party.update!(archived_at: Time.current)
        BookingAuditLog.create!(hotel: current_hotel, auditable: @booking, user: current_user,
          action_type: "billing_party_archived", category: "financial", source: "booking_workspace",
          occurred_at: Time.current, old_value: { billing_party_id: party.id, party: party.display_name })
        OpenStruct.new(success?: true)
      else
        OpenStruct.new(success?: false, error: "Billing parties with folios cannot be archived.")
      end
      redirect_with_result(result, tab: "billing_preferences")
    end

    def allocate_deposit
      deposit = group_booking.group_deposits.find(params[:group_deposit_id])
      folio = @booking.booking_folios.find(params[:booking_folio_id])
      result = ::GroupDeposits::Allocate.call(deposit: deposit, booking_folio: folio, amount: params[:amount], actor: current_user)
      redirect_with_result(result, tab: "folio_operations", folio_id: folio.id)
    end

    def refund_deposit
      deposit = group_booking.group_deposits.find(params[:group_deposit_id])
      result = ::GroupDeposits::RefundUnallocated.call(deposit: deposit, amount: params[:amount], actor: current_user, reason: params[:reason])
      redirect_with_result(result, tab: "folio_operations")
    end

    def reverse_deposit_allocation
      allocation = GroupDepositAllocation.joins(:group_deposit)
        .where(group_deposits: { group_booking_id: group_booking.id })
        .find(params[:group_deposit_allocation_id])
      result = ::GroupDeposits::ReverseAllocation.call(allocation: allocation, actor: current_user, reason: params[:reason])
      redirect_with_result(result, tab: "folio_operations", folio_id: allocation.booking_folio_id)
    end

    def collect_security_deposit
      folio = @booking.booking_folio || @booking.booking_folios.open.first || @booking.booking_folios.first
      result = ::Deposits::RecordSecurityDeposit.call(
        booking: @booking,
        folio: folio,
        user: current_user,
        amount: params[:amount],
        payment_method: params[:payment_method],
        external_reference: params[:external_reference]
      )
      redirect_with_result(result, tab: "security_deposits")
    end

    def release_security_deposits
      result = ::Deposits::ReleaseHeldDeposits.call(
        booking: @booking,
        user: current_user,
        released_at: Time.current,
        method: params[:method],
        reference: params[:reference]
      )
      redirect_with_result(result, tab: "security_deposits")
    end

    def complete_housekeeping_request
      result = update_request_status(kind: "housekeeping", request_id: params[:housekeeping_request_id], status: "completed")
      redirect_with_result(result, tab: "housekeeping_requests")
    end

    def resolve_complaint_request
      result = update_request_status(kind: "complaint", request_id: params[:complaint_request_id], status: "resolved")
      redirect_with_result(result, tab: "housekeeping_requests")
    end

    private

    def set_booking
      @booking = current_hotel.bookings.find(params[:booking_id])
    end

    def group_booking
      raise ActiveRecord::RecordNotFound unless @booking.group_booking_id.present?

      @group_booking ||= current_hotel.group_bookings.find(@booking.group_booking_id)
    end

    def scoped_group_bookings
      current_hotel.bookings.where(group_booking: group_booking)
    end

    def resolved_billing_party(result)
      return result.party if result.respond_to?(:party)

      Array(result.parties).find { |party| party.booking_id == @booking.id }
    end

    def room_rate_params
      params.fetch(:room_rate, {}).permit(:check_in, :check_out, :room_type_id, :room_number, :rate_plan_id, :manual_rate_override, :override, :override_reason)
    end

    def billing_party_params
      params.fetch(:billing_party, {}).permit(:hotel_corporate_account_id, :account_type, :settlement_type,
        :purchase_order_reference, :authorization_reference)
    end

    def billing_terms_params
      params.fetch(:billing_terms, {}).permit(:settlement_type, :purchase_order_reference, :authorization_reference)
    end

    def prepare_confirm_group_scope
      @group_bookings = scoped_group_bookings.includes(:booking_rooms, :booking_guests).order(:group_position, :id)
      @billing_party_attributes = billing_party_params
    end

    def authorize_manage_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
    end

    def update_request_status(kind:, request_id:, status:)
      return OpenStruct.new(success?: false, error: "Request does not belong to this booking.") unless request_belongs_to_booking?(kind, request_id)

      updater = ::HotelPortal::Requests::StatusUpdater.new(
        hotel: current_hotel,
        kind: kind,
        request_id: request_id,
        status: status
      )

      if updater.call
        OpenStruct.new(success?: true)
      else
        OpenStruct.new(success?: false, error: "Failed to update request.")
      end
    end

    def request_belongs_to_booking?(kind, request_id)
      case kind
      when "housekeeping"
        @booking.housekeeping_requests.exists?(request_id)
      when "complaint"
        @booking.complaint_requests.exists?(request_id)
      else
        false
      end
    end

    def redirect_with_result(result, **query)
      success = result.success?
      message = success ? "Booking workspace updated." : (result.respond_to?(:error) ? result.error : result.errors.to_a.to_sentence)
      redirect_to hotel_booking_workspace_path(current_hotel, @booking, query), success ? { notice: message } : { alert: message }
    end
    end
  end
end
