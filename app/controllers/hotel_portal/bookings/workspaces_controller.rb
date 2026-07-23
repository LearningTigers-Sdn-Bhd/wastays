# frozen_string_literal: true

module HotelPortal
  module Bookings
    class WorkspacesController < BaseController
      include BookingAuditable

    before_action :authorize_view_bookings!
    before_action :redirect_legacy_tab!
    before_action :require_audit_feature!, if: :audit_requested?

    def show
      @booking = current_hotel.bookings
        .includes(
          { booking_rooms: [ :room_type, :rate_plan ] },
          { booking_guests: :guest },
          :deposits,
          :payment_transactions,
          :refund_request,
          :housekeeping_requests,
          :complaint_requests,
          booking_billing_parties: [ :billing_terms, { booking_guest: :guest }, { hotel_corporate_account: :corporate_account }, :booking_folios ],
          booking_notes: :user,
          group_booking: [
            { bookings: [ :deposits, :housekeeping_requests, :complaint_requests, :folio_operation_logs, :booking_rooms, { booking_guests: :guest }, { booking_folios: [ :group_deposit_allocations, :folio_forecasted_charges, { folio_transactions: [ :user, :transaction_code ] } ] } ] },
            { group_deposits: :group_deposit_allocations }
          ],
          booking_folios: [ :ar_invoice, :group_deposit_allocations, :folio_forecasted_charges, { folio_transactions: [ :user, :transaction_code ] }, { hotel_corporate_account: :corporate_account } ],
          folio_routing_rules: [ :transaction_code, :target_folio, :created_by, :updated_by ],
          folio_operation_logs: [ :actor, :source_folio, :target_folio, :source_transaction, :target_transaction ]
        )
        .find(params[:booking_id])

      return if redirect_group_entity_context!

      @booking_presenter = BookingPresenter.new(@booking, current_hotel)
      @folio_show = Folios::ShowPresenter.new(
        booking: @booking,
        hotel: current_hotel,
        user: current_user,
        active_folio_id: params[:folio_id].presence || params[:active_folio_id].presence,
        active_tab: folio_show_tab
      )
      @presenter = HotelPortal::Bookings::WorkspacePresenter.new(@booking, params: params, hotel: current_hotel, booking_presenter: @booking_presenter, folio_show: @folio_show)
      set_audit_logs(@booking, group_booking: (@booking.group_booking if @presenter.group_overview?)) if @presenter.active_tab == "audit_trails"
      set_breadcrumbs(@booking)

      render partial: "hotel_portal/bookings/workspaces/work_area", locals: workspace_locals if turbo_frame_request?
    end

    def audit_trail
      @booking = current_hotel.bookings.find(params[:booking_id])
      @presenter = HotelPortal::Bookings::WorkspacePresenter.new(@booking, params: params, hotel: current_hotel)
      set_audit_logs(@booking)
    end

    private

    def audit_requested?
      action_name == "audit_trail" || params[:tab].to_s == "audit_trails"
    end

    def require_audit_feature!
      require_feature!("full_audit_trail")
    end

    def set_breadcrumbs(booking)
      override_breadcrumbs(
        { label: "Operations" },
        { label: "Reservations", path: hotel_front_desk_path(current_hotel, tab: "bookings", view: "list") },
        { label: booking.confirmation_token, path: hotel_booking_workspace_path(current_hotel, booking) },
        { label: "Booking Workspace" }
      )
    end

    def authorize_view_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end

    def folio_show_tab
      case params[:tab].to_s
      when "billing_details", "billing_preferences" then "billing_instructions"
      when "folio_operations" then "ledger"
      end
    end

    def workspace_locals
      {
        booking: @booking,
        presenter: @presenter,
        booking_presenter: @booking_presenter,
        folio_show: @folio_show,
        audit_logs: @audit_logs,
        audit_history: @audit_history
      }
    end

    def redirect_legacy_tab!
      replacement = { "room_charges" => "room_and_rate", "billing_details" => "billing_preferences" }[params[:tab].to_s]
      return if replacement.blank?

      redirect_to hotel_booking_workspace_path(current_hotel, params[:booking_id], request.query_parameters.merge(tab: replacement)), status: :see_other
    end

    def redirect_group_entity_context!
      tab = params[:tab].to_s
      entity_param = { "folio_operations" => "folio_id", "guest_details" => "booking_guest_id" }[tab]
      return false if entity_param.blank? || @booking.group_booking_id.blank?

      legacy_group_scope = params[:scope].to_s == "group"
      return false if params[entity_param].present? && !legacy_group_scope

      first_child = @booking.group_booking.bookings.min_by { |child| [ child.group_position || Float::INFINITY, child.id ] }
      return false unless first_child

      entity_id = if tab == "folio_operations"
        folios = first_child.booking_folios.to_a
        (folios.find(&:is_primary?) || folios.min_by { |folio| [ folio.folio_sequence.to_i, folio.id ] })&.id
      else
        guests = first_child.booking_guests.to_a
        (guests.find(&:is_primary?) || guests.min_by(&:id))&.id
      end

      query = request.query_parameters.except("scope", "folio_id", "active_folio_id", "booking_guest_id")
      query[entity_param] = entity_id if entity_id
      return false if !legacy_group_scope && first_child.id == @booking.id && entity_id.blank?

      redirect_to hotel_booking_workspace_path(current_hotel, first_child, query), status: :see_other
      true
    end
    end
  end
end
