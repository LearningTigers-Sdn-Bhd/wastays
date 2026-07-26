# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "add folio window" and "edit folio window".
      #
      # One controller, two forms. Creating asks *whose* folio this is — you
      # pick a booking and one of its billing parties, and
      # BookingWorkspaces::CreateFolioWindow derives folio_type and payer_type
      # from that party. Editing asks *what* the folio should be — type, payer,
      # corporate account, and primary status are set directly.
      class WindowsController < BaseController
        def show
          return update if request.patch?
          return create if request.post?

          editing? ? load_folio : load_creation_options
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_windows")
        end

        def editing?
          params[:folio_id].present?
        end

        def load_folio
          @folio = @booking.booking_folios.find(params[:folio_id])
          @company_government_accounts = company_government_accounts
        end

        def load_creation_options
          @folio_booking_options = folio_booking_options
        end

        def create
          target_booking = creation_booking
          result = ::BookingWorkspaces::CreateFolioWindow.call(
            booking: target_booking,
            user: current_user,
            attributes: creation_params
          )

          return complete_action(alert: result.error) unless result.success?

          # A group booking can create the folio on a sibling, so the default
          # destination has to follow the folio, not the path booking.
          default_return_to(result.folio.booking, result.folio)
          complete_action(notice: "Folio window created.")
        end

        def update
          folio = @booking.booking_folios.find(params[:folio_id])
          result = ::Folios::Lifecycle::UpdateFolio.call(folio: folio, user: current_user, attributes: folio_params)

          return complete_action(alert: result.error) unless result.success?

          default_return_to(@booking, folio)
          complete_action(notice: "Folio window updated.")
        end

        # Keeps an explicit return_to authoritative; only fills the fallback.
        def default_return_to(booking, folio)
          return if params[:return_to].present?

          @return_to = hotel_booking_workspace_path(current_hotel, booking, tab: "folio_operations", folio_id: folio.id)
        end

        # A group booking can create a folio on any of its child bookings, so a
        # submitted booking overrides the one in the path — but only within the
        # same group.
        def creation_booking
          requested_id = params.dig(:folio_window, :booking_id).presence
          return @booking if requested_id.blank? || requested_id.to_s == @booking.id.to_s

          raise ActiveRecord::RecordNotFound unless @booking.group_booking_id?

          current_hotel.bookings.where(group_booking_id: @booking.group_booking_id).find(requested_id)
        end

        def creation_params
          params.fetch(:folio_window, {}).permit(:booking_billing_party_id, :label, :currency, :reason)
        end

        def folio_params
          params.fetch(:booking_folio, {}).permit(
            :label, :folio_type, :payer_type, :payer_id, :hotel_corporate_account_id, :currency,
            :reason, :settlement_method, :is_primary, :set_folio_as_primary_reason
          )
        end

        def company_government_accounts
          current_hotel.hotel_corporate_accounts
                       .active
                       .includes(corporate_account: :users)
                       .order(created_at: :desc)
        end

        def folio_booking_options
          bookings = if @booking.group_booking_id?
            current_hotel.bookings
                         .where(group_booking_id: @booking.group_booking_id)
                         .includes(:booking_rooms, booking_billing_parties: [ :booking_guest, { hotel_corporate_account: :corporate_account } ])
                         .order(:group_position, :id)
          else
            current_hotel.bookings
                         .where(id: @booking.id)
                         .includes(:booking_rooms, booking_billing_parties: [ :booking_guest, { hotel_corporate_account: :corporate_account } ])
          end

          bookings.map do |booking|
            room = booking.booking_rooms.first
            room_label = room&.room_number.present? ? "Room #{room.room_number}" : "Unassigned room"
            number = booking.formatted_reservation_number.presence || "—"
            {
              booking: booking,
              label: "#{room_label} · Booking No. #{number}",
              parties: booking.booking_billing_parties.active.to_a.sort_by { |party| party.display_name.to_s.downcase }
            }
          end
        end
      end
    end
  end
end
