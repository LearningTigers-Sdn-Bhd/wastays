# frozen_string_literal: true

module HotelPortal
  # Single source of truth for what a front desk record can do.
  #
  # The table and the stay card render the same list two ways — the table
  # surfaces the primary action as a button and keeps the rest in an overflow
  # menu, the card keeps everything in the menu because it has no room. Before
  # this the two were written separately and had drifted: the table said
  # "Check In" where the card said "Check in", offered no print or audit entry
  # at all, and gave departures no way to check a guest out in list view.
  module FrontDeskHelper
    def front_desk_actions(booking, tab:)
      actions = [ open_action(booking, tab) ]
      actions.concat(lifecycle_actions(booking, tab))
      actions << print_action(booking, tab)
      actions << audit_trail_action(booking)
      actions.compact
    end

    private

    def open_action(booking, tab)
      {
        label: tab == "bookings" ? "Open booking" : "View booking",
        path: hotel_booking_workspace_path(current_hotel, booking, tab: "booking_details"),
        data: tab == "bookings" ? { turbo_frame: "_top" } : {}
      }
    end

    # State changes are the primary action when one applies, and all of them
    # require manage_bookings — in-house used to let anyone check a guest out
    # while departures required the permission for the same operation.
    def lifecycle_actions(booking, tab)
      return [] unless tab.in?(%w[arrivals in_house departures])
      return [] unless current_user.has_permission?("manage_bookings", hotel: current_hotel)

      case [ tab, booking.status ]
      in [ "arrivals", "confirmed" ] then [ sheet_action(booking, "Check in", :check_in) ]
      in [ "arrivals", "checked_in" ] then [ sheet_action(booking, "Edit check-in time", :check_in) ]
      in [ _, "due_out_detected" ] then [ sheet_action(booking, "Resolve due-out", :late_checkout) ]
      in [ _, "checkout_required" ] then [ sheet_action(booking, "Complete checkout", :checkout) ]
      in [ "in_house" | "departures", "checked_in" ] then [ sheet_action(booking, "Check out", :checkout) ]
      else []
      end
    end

    def sheet_action(booking, label, action)
      path = public_send(:"hotel_booking_action_#{action}_path", current_hotel, booking, return_to: request.fullpath)
      { label:, path:, primary: true, data: { turbo_frame: "booking_action_sheet" } }
    end

    def print_action(booking, tab)
      return unless current_user.has_permission?("manage_bookings", hotel: current_hotel)

      if tab.in?(%w[bookings arrivals])
        # A group arriving together is checked in as a block, so the useful thing to hand
        # the desk is the whole pack rather than one room's page.
        if booking.group_booking_id?
          { label: "Print group vouchers", path: pack_hotel_booking_reservation_voucher_path(current_hotel, booking), target: "_blank", data: { turbo: false } }
        else
          { label: "Print reservation voucher", path: hotel_booking_reservation_voucher_path(current_hotel, booking), target: "_blank", data: { turbo: false } }
        end
      else
        { label: "Print invoice", path: invoice_booking_path(booking.confirmation_token), target: "_blank", data: { turbo: false } }
      end
    end

    def audit_trail_action(booking)
      return unless current_user.has_permission?("view_bookings", hotel: current_hotel)
      return unless current_hotel.feature_enabled?("full_audit_trail")

      { label: "Audit trail", path: hotel_booking_action_audit_trail_path(current_hotel, booking), data: { turbo_frame: "booking_action_sheet" } }
    end
  end
end
