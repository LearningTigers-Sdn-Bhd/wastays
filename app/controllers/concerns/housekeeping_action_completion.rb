# frozen_string_literal: true

# Sheet-based completion contract for HotelPortal::HousekeepingTasks::Actions.
#
# Binds SheetActionCompletion to the `housekeeping_action_sheet` frame, the way
# BookingActionCompletion and FolioActionCompletion bind their own, so a sheet
# launched from the housekeeping board closes its own dialog on completion.
module HousekeepingActionCompletion
  extend ActiveSupport::Concern
  include SheetActionCompletion

  DEFAULT_FRAME = "housekeeping_action_sheet"

  private

  def complete_housekeeping_action(destination:, notice:, html_status: :see_other, frame: DEFAULT_FRAME)
    complete_sheet_action(destination: destination, notice: notice, html_status: html_status, frame: frame)
  end

  def housekeeping_action_return_to(fallback:)
    sheet_action_return_to(fallback: fallback)
  end
end
