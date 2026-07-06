# frozen_string_literal: true

require "ostruct"

module HotelPortal
  class BookingControlPanelActionsController < BaseController
    include OffcanvasTransactionCompletion

    before_action :authorize_manage_bookings!, except: %i[new_folio_window create_folio_window]
    before_action :authorize_manage_folio_windows!, only: %i[new_folio_window create_folio_window]
    before_action :authorize_manage_billing_routes!, only: %i[billing_routes preview_billing_routes apply_billing_routes
      group_billing_routes preview_group_billing_routes apply_group_billing_routes]
    before_action :set_booking

    def new_folio_window
      @booking_presenter = BookingPresenter.new(@booking, current_hotel)
      @folio_show = Folios::ShowPresenter.new(booking: @booking, hotel: current_hotel, user: current_user, active_folio_id: params[:folio_id])
      @presenter = BookingControlPanelPresenter.new(@booking, params: params.merge(tab: "folio_operations"), hotel: current_hotel, booking_presenter: @booking_presenter, folio_show: @folio_show)

      render "hotel_portal/booking_control_panels/actions/create_folio_window/offcanvas"
    end

    def create_folio_window
      result = ::BookingControlPanels::CreateFolioWindow.call(
        booking: @booking,
        user: current_user,
        attributes: create_folio_window_params
      )

      destination = hotel_booking_control_panel_path(
        current_hotel,
        @booking,
        tab: "folio_operations",
        folio_id: result.folio&.id
      )

      if result.success?
        respond_to do |format|
          format.turbo_stream do
            flash[:notice] = "Folio window created."
            render_offcanvas_completion(destination)
          end
          format.html { redirect_to destination, notice: "Folio window created.", status: :see_other }
        end
      else
        redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "folio_operations"), alert: result.error, status: :see_other
      end
    end

    def set_primary_guest
      booking_guest = @booking.booking_guests.find(params[:booking_guest_id])
      result = ::Bookings::SetPrimaryGuest.call(booking: @booking, booking_guest: booking_guest, actor: current_user)
      redirect_with_result(result, tab: "guest_details", booking_guest_id: booking_guest.id)
    end

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

    def apply_billing
      arrangement = group_booking.group_billing_arrangements.find(params[:group_billing_arrangement_id])
      bookings = scoped_group_bookings.where(id: Array(params[:booking_ids]).presence || @booking.id)
      result = ::Billing::ApplyGroupArrangement.call(
        arrangement: arrangement,
        bookings: bookings,
        charge_categories: Array(params[:charge_categories]),
        actor: current_user,
        local_exception: ActiveModel::Type::Boolean.new.cast(params[:local_exception]),
        replace_local_exceptions: ActiveModel::Type::Boolean.new.cast(params[:replace_local_exceptions])
      )
      redirect_with_result(result, tab: "billing_preferences", billing_scope: params[:billing_scope], scope: ("group" if params[:billing_scope] == "group"))
    end

    def group_billing_routes
      prepare_group_billing_routes
      render "hotel_portal/booking_control_panels/actions/group_billing_routes/offcanvas"
    end

    def preview_group_billing_routes
      prepare_group_billing_routes
      @group_draft = group_billing_change_params
      @group_preview = ::GroupBillingChanges::Batch.preview(**group_billing_change_arguments)
      flash.now[:alert] = @group_preview.error unless @group_preview.success?
      render "hotel_portal/booking_control_panels/actions/group_billing_routes/offcanvas",
        status: (@group_preview.success? ? :ok : :unprocessable_entity)
    end

    def apply_group_billing_routes
      prepare_group_billing_routes
      @group_draft = group_billing_change_params
      result = ::GroupBillingChanges::Batch.call(**group_billing_change_arguments.merge(
        confirmation: params[:confirmation], forecast_confirmation: params[:forecast_confirmation],
        reason: params[:reason], freshness_token: params[:freshness_token]))
      destination = hotel_booking_control_panel_path(current_hotel, @booking, tab: "billing_preferences",
        billing_scope: "group", scope: "group")
      if result.success?
        respond_to do |format|
          format.turbo_stream do
            flash[:notice] = "Group billing routes updated."
            render_offcanvas_completion(destination)
          end
          format.html { redirect_to destination, notice: "Group billing routes updated.", status: :see_other }
        end
      else
        @group_preview = ::GroupBillingChanges::Batch.preview(**group_billing_change_arguments)
        flash.now[:alert] = result.error
        render "hotel_portal/booking_control_panels/actions/group_billing_routes/offcanvas", status: :unprocessable_entity
      end
    end

    def add_billing_party
      result = ::BookingBillingParties::ManageCompany.call(
        booking: @booking, actor: current_user, attributes: billing_party_params
      )
      redirect_with_result(result, tab: "billing_preferences", billing_party_id: result.party&.id)
    end

    def update_billing_terms
      party = @booking.booking_billing_parties.active.find(params[:billing_party_id])
      result = ::BookingBillingParties::UpdateTerms.call(
        party: party, actor: current_user, attributes: billing_terms_params
      )
      redirect_with_result(result, tab: "billing_preferences", billing_party_id: party.id)
    end

    def archive_billing_party
      party = @booking.booking_billing_parties.companies.active.find(params[:billing_party_id])
      result = if party.archiveable?
        party.update!(archived_at: Time.current)
        BookingAuditLog.create!(hotel: current_hotel, auditable: @booking, user: current_user,
          action_type: "billing_party_archived", category: "financial", source: "booking_control_panel",
          occurred_at: Time.current, old_value: { billing_party_id: party.id, party: party.display_name })
        OpenStruct.new(success?: true)
      else
        OpenStruct.new(success?: false, error: "Billing parties with folios cannot be archived.")
      end
      redirect_with_result(result, tab: "billing_preferences")
    end

    def create_group_billing_arrangement
      result = ::Billing::SaveGroupArrangement.call(
        group_booking: group_booking, actor: current_user, attributes: group_billing_arrangement_params
      )
      redirect_with_result(result, tab: "billing_preferences", scope: "group", arrangement_id: result.arrangement&.id)
    end

    def update_group_billing_arrangement
      arrangement = group_booking.group_billing_arrangements.find(params[:group_billing_arrangement_id])
      result = ::Billing::SaveGroupArrangement.call(
        group_booking: group_booking, arrangement: arrangement, actor: current_user,
        attributes: group_billing_arrangement_params
      )
      redirect_with_result(result, tab: "billing_preferences", scope: "group", arrangement_id: arrangement.id)
    end

    def deactivate_group_billing_arrangement
      arrangement = group_booking.group_billing_arrangements.find(params[:group_billing_arrangement_id])
      result = ::Billing::SaveGroupArrangement.call(
        group_booking: group_booking, arrangement: arrangement, actor: current_user,
        attributes: { status: "inactive" }
      )
      redirect_with_result(result, tab: "billing_preferences", scope: "group")
    end

    def apply_routing
      rule = @booking.folio_routing_rules.find(params[:folio_routing_rule_id])
      result = ::FolioRouting::ApplyExistingCharges.call(
        rule: rule,
        actor: current_user,
        reason: params[:reason],
        confirmation: params[:confirmation]
      )
      redirect_with_result(result, tab: "billing_preferences")
    end

    def billing_routes
      prepare_billing_routes
      render "hotel_portal/booking_control_panels/actions/billing_routes/offcanvas"
    end

    def preview_billing_routes
      prepare_billing_routes
      @route_draft = billing_routes_params
      @batch_preview = ::FolioRouting::ApplyBatch.preview(booking: @booking, routes: @route_draft)
      if @batch_preview.success? && !@batch_preview.review_required?
        return apply_billing_routes
      end

      flash.now[:alert] = @batch_preview.error unless @batch_preview.success?
      render "hotel_portal/booking_control_panels/actions/billing_routes/offcanvas", status: (@batch_preview.success? ? :ok : :unprocessable_entity)
    end

    def apply_billing_routes
      result = ::FolioRouting::ApplyBatch.call(
        booking: @booking, actor: current_user, routes: billing_routes_params,
        confirmation: params[:confirmation], forecast_confirmation: params[:forecast_confirmation],
        reason: params[:reason], idempotency_key: params[:idempotency_key]
      )
      destination = hotel_booking_control_panel_path(current_hotel, @booking, tab: "billing_preferences")
      if result.success?
        respond_to do |format|
          format.turbo_stream do
            flash[:notice] = "Billing routes updated."
            render_offcanvas_completion(destination)
          end
          format.html { redirect_to destination, notice: "Billing routes updated.", status: :see_other }
        end
      else
        prepare_billing_routes
        @route_draft = billing_routes_params
        @batch_preview = ::FolioRouting::ApplyBatch.preview(booking: @booking, routes: @route_draft)
        flash.now[:alert] = result.error
        render "hotel_portal/booking_control_panels/actions/billing_routes/offcanvas", status: :unprocessable_entity
      end
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
      raise ActiveRecord::RecordNotFound unless BookingRedesign.enabled? && @booking.group_booking_id.present?

      @group_booking ||= current_hotel.group_bookings.find(@booking.group_booking_id)
    end

    def scoped_group_bookings
      current_hotel.bookings.where(group_booking: group_booking)
    end

    def room_rate_params
      params.fetch(:room_rate, {}).permit(:check_in, :check_out, :room_type_id, :room_number, :rate_plan_id, :manual_rate_override, :override, :override_reason)
    end

    def create_folio_window_params
      params.fetch(:folio_window, {}).permit(:booking_billing_party_id, :name, :currency, :reason)
    end

    def billing_party_params
      params.fetch(:billing_party, {}).permit(:hotel_corporate_account_id, :settlement_type,
        :preferred_payment_method, :purchase_order_reference, :billing_reference, :authorization_reference)
    end

    def billing_terms_params
      params.fetch(:billing_terms, {}).permit(:settlement_type, :preferred_payment_method,
        :purchase_order_reference, :billing_reference, :authorization_reference)
    end

    def billing_routes_params
      params.fetch(:routes, {}).permit!.to_h
    end

    def group_billing_change_params
      params.permit(:group_billing_arrangement_id, :replace_local_exceptions, :idempotency_key,
        booking_ids: [], charge_categories: [], inclusion_changes: {}).to_h
    end

    def group_billing_change_arguments
      draft = @group_draft || group_billing_change_params
      {
        group_booking: group_booking,
        actor: current_user,
        booking_ids: draft["booking_ids"],
        arrangement_id: draft["group_billing_arrangement_id"],
        categories: draft["charge_categories"],
        inclusion_changes: draft["inclusion_changes"] || {},
        replace_local_exceptions: draft["replace_local_exceptions"],
        idempotency_key: draft["idempotency_key"]
      }
    end

    def prepare_billing_routes
      @routing_matrix = ::FolioRouting::RoutingMatrix.new(booking: @booking)
      @batch_key = params[:idempotency_key].presence || SecureRandom.uuid
    end

    def prepare_group_billing_routes
      @group = group_booking
      @group_children = scoped_group_bookings.includes(:booking_guests, :booking_folios).order(:group_position, :id)
      @group_arrangements = @group.group_billing_arrangements.active.includes(hotel_corporate_account: :corporate_account)
      @group_codes = ::FolioRouting::RoutabilityPolicy.parent_codes(hotel: current_hotel)
        .where(category: ::GroupBillingChanges::Batch::CATEGORIES).includes(:transaction_code_taxes)
      @group_tax_candidates = ::FolioRouting::RoutingMatrix.new(booking: @booking).rows
        .flat_map(&:children).uniq(&:key)
      @group_batch_key = params[:idempotency_key].presence || SecureRandom.uuid
    end

    def group_billing_arrangement_params
      params.fetch(:group_billing_arrangement, {}).permit(:name, :payer_type,
        :hotel_corporate_account_id, :settlement_type, :preferred_payment_method,
        :purchase_order_reference, :billing_reference, :authorization_reference,
        :valid_from, :valid_until, :status, charge_categories: [])
    end

    def authorize_manage_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
    end

    def authorize_manage_folio_windows!
      allowed = current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
        current_user.has_permission?("manage_folio_windows", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end

    def authorize_manage_billing_routes!
      allowed = current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
        current_user.has_permission?("manage_folio_movements", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
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
      message = success ? "Booking control panel updated." : (result.respond_to?(:error) ? result.error : result.errors.to_a.to_sentence)
      redirect_to hotel_booking_control_panel_path(current_hotel, @booking, query), success ? { notice: message } : { alert: message }
    end
  end
end
