# frozen_string_literal: true

module HotelPortal
  module Bookings
    class WorkspacesController < BaseController
      include BookingAuditable

    before_action :authorize_view_bookings!
    before_action :authorize_manage_bookings!, only: :update
    before_action :redirect_legacy_tab!
    before_action :require_audit_feature!, if: :audit_requested?
    before_action :set_workspace_booking, only: %i[show update]

    def show
      prepare_workspace
      if @presenter.active_tab == "audit_trails"
        set_audit_logs(@presenter.audit_selected_booking || @booking, group_booking: (@booking.group_booking if @presenter.audit_group_scope?))
      end
      set_breadcrumbs(@booking, @presenter)

      render partial: "hotel_portal/bookings/workspaces/work_area", locals: workspace_locals if turbo_frame_request?
    end

    def update
      booking_guest = @booking.booking_guests.find(params[:booking_guest_id])
      prepare_workspace
      raise ActiveRecord::RecordNotFound unless @presenter.selected_booking_guest == booking_guest && @entity_booking == @booking

      guest_form = booking_guest.guest.dup
      guest_form.assign_attributes(guest_params)
      guest_form.valid?
      booking_guest_form = booking_guest.dup
      booking_guest_form.assign_attributes(booking_guest_bibo_params)
      booking_guest_form.valid?

      result = BookingGuests::UpdateSnapshot.call(
        booking_guest: booking_guest,
        attributes: guest_params,
        actor: current_user,
        update_profile: save_scope == "snapshot_and_profile",
        bibo_attributes: booking_guest_bibo_params
      )

      if result.success?
        notice = save_scope == "snapshot_and_profile" ? "Guest details and guest record updated." : "Guest details saved."
        redirect_to hotel_booking_workspace_path(current_hotel, @entity_booking, tab: "guest_details", booking_guest_id: booking_guest.id), notice:, status: :see_other
      else
        result.errors.each do |error|
          guest_form.errors.add(:base, error) unless guest_form.errors.full_messages.include?(error)
        end
        prepare_workspace(guest_form:, booking_guest_form:)
        set_breadcrumbs(@booking, @presenter)
        render :show, status: :unprocessable_content
      end
    end

    def audit_trail
      @booking = current_hotel.bookings.find(params[:booking_id])
      @presenter = HotelPortal::Bookings::WorkspacePresenter.new(@booking, params: params, hotel: current_hotel, user: current_user)
      set_audit_logs(@presenter.audit_selected_booking || @booking, group_booking: (@booking.group_booking if @presenter.audit_group_scope?))
    end

    private

    def set_workspace_booking
      scope = current_hotel.bookings
      scope = scope.includes(
          { booking_rooms: [ :room_type, :rate_plan ] },
          { booking_guests: :guest },
          :hotel,
          { deposits: { deposit_movements: [ :booking_folio, :folio_transaction ] } },
          :payment_transactions,
          :refund_request,
          :housekeeping_requests,
          :complaint_requests,
          booking_billing_parties: [ :billing_terms, { booking_guest: :guest }, { hotel_corporate_account: :corporate_account }, :booking_folios ],
          booking_notes: :user,
          group_booking: [
            { bookings: [ :hotel, :booking_folio, { deposits: { deposit_movements: [ :booking_folio, :folio_transaction ] } }, :housekeeping_requests, :complaint_requests, :folio_operation_logs, { booking_rooms: [ :room_type, :rate_plan ] }, { booking_guests: :guest }, { booking_billing_parties: [ :billing_terms, :booking_folios, { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ] }, { booking_folios: [ :deposit_movements, :folio_forecasted_charges, { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ] }, { folio_transactions: [ :user, :transaction_code ] }, { hotel_corporate_account: :corporate_account } ] } ] },
            { deposits: { deposit_movements: [ :booking_folio, :folio_transaction ] } }
          ],
          booking_folios: [ :ar_invoice, :deposit_movements, :folio_forecasted_charges, { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ] }, { folio_transactions: [ :user, :transaction_code ] }, { hotel_corporate_account: :corporate_account } ],
          folio_routing_rules: [ :transaction_code, :target_folio, :created_by, :updated_by ],
          folio_operation_logs: [ :actor, :source_folio, :target_folio, :source_transaction, :target_transaction ]
        )
      @booking = scope.find(params[:booking_id])
    end

    def prepare_workspace(guest_form: nil, booking_guest_form: nil)
      @booking_presenter = BookingPresenter.new(@booking, current_hotel)
      @presenter = HotelPortal::Bookings::WorkspacePresenter.new(
        @booking,
        params: params,
        hotel: current_hotel,
        user: current_user,
        booking_presenter: @booking_presenter,
        guest_form: guest_form,
        booking_guest_form: booking_guest_form
      )
      if @presenter.active_tab == "documents"
        @invoice_delivery_preview = Notifications::InvoiceDelivery.preview(
          hotel: current_hotel,
          bookings: @presenter.document_context_bookings
        )
      end
      @entity_booking = @presenter.selected_child_booking
      @folio_show = Folios::ShowPresenter.new(
        booking: @entity_booking,
        hotel: current_hotel,
        user: current_user,
        active_folio_id: @presenter.selected_folio&.id,
        active_tab: folio_show_tab
      )
    end

    def audit_requested?
      action_name == "audit_trail" || params[:tab].to_s == "audit_trails"
    end

    def require_audit_feature!
      require_feature!("full_audit_trail")
    end

    def set_breadcrumbs(booking, presenter)
      override_breadcrumbs(
        { label: "Operations" },
        { label: "Reservations", path: hotel_front_desk_path(current_hotel, tab: "bookings", view: "list") },
        { label: presenter.group_context_enabled? ? presenter.group_booking_number : presenter.booking_number, path: presenter.group_overview_header_path || hotel_booking_workspace_path(current_hotel, booking) },
        { label: "Booking Workspace" }
      )
    end

    def authorize_view_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end

    def authorize_manage_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
    end

    def save_scope
      params[:save_scope].presence_in(%w[snapshot snapshot_and_profile]) || "snapshot"
    end

    def guest_params
      params.require(:guest).permit(:name, :email, :phone, :country, :gender, :document_type, :government_id, :date_of_birth, :home_address)
    end

    # The form posts a time-of-day per slot; the stay supplies the calendar day.
    def booking_guest_bibo_params
      ::Boats::ResolveTimes.call(
        hotel: current_hotel,
        check_in: @booking.check_in,
        check_out: @booking.check_out,
        params: params.fetch(:booking_guest, {})
      )
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
        entity_booking: @entity_booking,
        presenter: @presenter,
        booking_presenter: @booking_presenter,
        folio_show: @folio_show,
        audit_logs: @audit_logs,
        audit_history: @audit_history,
        audit_category: @audit_category,
        audit_history_available: @audit_history_available
      }
    end

    def redirect_legacy_tab!
      replacement = { "room_charges" => "room_and_rate", "billing_details" => "billing_preferences" }[params[:tab].to_s]
      return if replacement.blank?

      redirect_to hotel_booking_workspace_path(current_hotel, params[:booking_id], request.query_parameters.merge(tab: replacement)), status: :see_other
    end
    end
  end
end
