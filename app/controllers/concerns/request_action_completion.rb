# frozen_string_literal: true

# Sheet-based completion contract for HotelPortal::Requests::Actions.
#
# Binds SheetActionCompletion to the `requests_action_sheet` frame, the way
# BookingActionCompletion and HousekeepingActionCompletion bind their own, so a
# sheet launched from the requests board closes its own dialog on completion.
module RequestActionCompletion
  extend ActiveSupport::Concern
  include SheetActionCompletion

  DEFAULT_FRAME = "requests_action_sheet"

  private

  def complete_request_action(destination:, notice:, html_status: :see_other, frame: DEFAULT_FRAME)
    complete_sheet_action(destination: destination, notice: notice, html_status: html_status, frame: frame)
  end

  def request_action_return_to(fallback:)
    sheet_action_return_to(fallback: fallback)
  end
end
