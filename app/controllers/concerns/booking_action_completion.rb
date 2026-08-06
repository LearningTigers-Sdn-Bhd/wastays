# frozen_string_literal: true

# Sheet-based completion contract for HotelPortal::Bookings::Actions.
#
# Binds SheetActionCompletion to the `booking_action_sheet` frame. Deliberately
# isolated from OffcanvasTransactionCompletion: it targets a different frame and
# a different stream action, and shares no names or helpers with the legacy
# Offcanvas implementation.
module BookingActionCompletion
  extend ActiveSupport::Concern
  include SheetActionCompletion

  DEFAULT_FRAME = "booking_action_sheet"

  private

  def complete_booking_action(destination:, notice:, html_status: :see_other, frame: DEFAULT_FRAME)
    complete_sheet_action(destination: destination, notice: notice, html_status: html_status, frame: frame)
  end

  def render_booking_action_completion(destination, frame: DEFAULT_FRAME)
    render_sheet_action_completion(destination, frame: frame)
  end

  def booking_action_return_to(fallback:)
    sheet_action_return_to(fallback: fallback)
  end
end
