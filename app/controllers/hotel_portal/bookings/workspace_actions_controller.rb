# frozen_string_literal: true

module HotelPortal
  module Bookings
    class WorkspaceActionsController < BaseController
    ActionResult = ApplicationResult.define

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
        ActionResult.success
      else
        ActionResult.failure("Billing parties with folios cannot be archived.")
      end
      redirect_with_result(result, tab: "billing_preferences")
    end

    def allocate_deposit
      deposit = accessible_deposits.find(params[:deposit_id] || params[:group_deposit_id])
      folio = eligible_folios_for(deposit).find(params[:booking_folio_id])
      result = if deposit.kind_security?
        code = current_hotel.transaction_codes.active.charge
          .where(system_key: Deposits::Deduct::ALLOWED_REASON_KEYS).find_by(id: params[:transaction_code_id])
        ::Deposits::Deduct.call(
          deposit: deposit,
          booking_folio: folio,
          amount: params[:amount],
          transaction_code: code,
          actor: current_user,
          posting_date: current_hotel.current_business_date,
          details: params[:details],
          operation_key: params[:operation_key]
        )
      else
        ::Deposits::Apply.call(
          deposit: deposit, booking_folio: folio, amount: params[:amount], actor: current_user,
          reason: params[:reason], operation_key: params[:operation_key]
        )
      end
      redirect_with_result(result, tab: "folio_operations", folio_id: folio.id)
    end

    def record_deposit
      owner = deposit_owner_from_param
      result = record_workspace_deposit(owner)
      redirect_with_result(result, tab: "security_deposits", scope: ("group" if owner.is_a?(GroupBooking)))
    end

    def return_deposit
      refund_deposit
    end

    def refund_deposit
      deposit = accessible_deposits.find(params[:deposit_id] || params[:group_deposit_id])
      result = ::Deposits::Return.call(
        deposit: deposit, amount: params[:amount], actor: current_user, reason: params[:reason],
        payment_method: params[:payment_method], external_reference: params[:external_reference],
        operation_key: params[:operation_key]
      )
      redirect_with_result(result, tab: "security_deposits")
    end

    def reverse_deposit_application
      movement = DepositMovement.joins(:deposit)
        .where(deposits: { id: accessible_deposits.select(:id) })
        .find(params[:deposit_movement_id] || params[:group_deposit_allocation_id])
      result = ::Deposits::ReverseApplication.call(
        movement: movement, actor: current_user, reason: params[:reason], operation_key: params[:operation_key]
      )
      redirect_with_result(result, tab: "folio_operations", folio_id: movement.booking_folio_id)
    end

    alias_method :reverse_deposit_allocation, :reverse_deposit_application

    def collect_security_deposit
      folio = @booking.booking_folio || @booking.booking_folios.open.first || @booking.booking_folios.first
      result = ::Deposits::Record.call(
        owner: @booking,
        kind: "security",
        actor: current_user,
        amount: params[:amount],
        currency: folio.currency,
        payment_method: params[:payment_method],
        external_reference: params[:external_reference]
      )
      redirect_with_result(result, tab: "security_deposits")
    end

    def release_security_deposits
      movements = []
      error = nil
      Deposit.transaction do
        @booking.deposits.kind_security.where(status: "held").find_each do |deposit|
          result = ::Deposits::Return.call(
            deposit: deposit, amount: deposit.available_amount, actor: current_user,
            payment_method: params[:method], external_reference: params[:reference],
            operation_key: params[:operation_key].presence && "#{params[:operation_key]}:#{deposit.id}"
          )
          unless result.success?
            error = result.error
            raise ActiveRecord::Rollback
          end

          movements << result.movement
        end
      end
      result = error ? Deposits::BatchResult.failure(error, movements: []) : Deposits::BatchResult.success(movements: movements)
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

    def record_workspace_deposit(owner)
      result = nil
      Deposit.transaction do
        result = ::Deposits::Record.call(
          owner: owner,
          kind: params[:kind],
          amount: params[:amount],
          currency: owner.respond_to?(:currency) ? owner.currency : current_hotel.default_currency,
          payment_method: params[:payment_method],
          external_reference: params[:external_reference],
          actor: current_user,
          operation_key: params[:operation_key],
          metadata: { source: "booking_workspace" }
        )
        raise ActiveRecord::Rollback unless result.success?
        next unless result.deposit.kind_prepayment? && owner.is_a?(Booking)

        folio = owner.booking_folio || owner.booking_folios.open.first || owner.booking_folios.first
        unless folio
          result = Deposits::MovementResult.failure("Create a booking folio before recording a prepayment.", deposit: result.deposit)
          raise ActiveRecord::Rollback
        end

        result = ::Deposits::Apply.call(
          deposit: result.deposit,
          booking_folio: folio,
          amount: result.deposit.amount,
          actor: current_user,
          operation_key: "workspace-prepayment:#{result.deposit.id}"
        )
        raise ActiveRecord::Rollback unless result.success?
      end
      result
    end

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

    def accessible_deposits
      booking_scope = current_hotel.deposits.where(booking_id: @booking.id)
      return booking_scope if @booking.group_booking_id.blank?

      group_scope = current_hotel.deposits.where(group_booking_id: @booking.group_booking_id)
      child_scope = current_hotel.deposits.where(booking_id: group_booking.bookings.select(:id))
      group_scope.or(child_scope)
    end

    def eligible_folios_for(deposit)
      scope = current_hotel.booking_folios.where(currency: deposit.currency)
      scope = if deposit.booking_id.present?
        scope.where(booking_id: deposit.booking_id)
      else
        scope.joins(:booking).where(bookings: { group_booking_id: deposit.group_booking_id })
      end
      scope = scope.where(hotel_corporate_account_id: deposit.hotel_corporate_account_id) if deposit.hotel_corporate_account_id.present?
      scope
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

    def deposit_owner_from_param
      type, id = params[:owner].to_s.split(":", 2)
      return @booking if type.blank? && id.blank?
      return current_hotel.bookings.find(id) if type == "booking" && accessible_booking_ids.include?(id.to_i)
      return group_booking if type == "group" && group_booking.id == id.to_i

      raise ActiveRecord::RecordNotFound
    end

    def accessible_booking_ids
      @accessible_booking_ids ||= if @booking.group_booking_id.present?
        group_booking.bookings.where(hotel_id: current_hotel.id).pluck(:id)
      else
        [ @booking.id ]
      end
    end

    def authorize_manage_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
    end

    def update_request_status(kind:, request_id:, status:)
      return ActionResult.failure("Request does not belong to this booking.") unless request_belongs_to_booking?(kind, request_id)

      updater = ::HotelPortal::Requests::StatusUpdater.new(
        hotel: current_hotel,
        kind: kind,
        request_id: request_id,
        status: status
      )

      if updater.call
        ActionResult.success
      else
        ActionResult.failure("Failed to update request.")
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
