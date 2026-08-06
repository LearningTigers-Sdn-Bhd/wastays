# frozen_string_literal: true

# Sheet-based completion contract for HotelPortal::Folios::Actions.
#
# Binds SheetActionCompletion to the `folio_action_sheet` frame. Folio actions
# remain their own family: they share no frames with BookingActionCompletion or
# the legacy OffcanvasTransactionCompletion.
module FolioActionCompletion
  extend ActiveSupport::Concern
  include SheetActionCompletion

  DEFAULT_FRAME = "folio_action_sheet"

  private

  def complete_folio_action(destination:, notice:, html_status: :see_other, frame: DEFAULT_FRAME)
    complete_sheet_action(destination: destination, notice: notice, html_status: html_status, frame: frame)
  end

  def render_folio_action_completion(destination, frame: DEFAULT_FRAME)
    render_sheet_action_completion(destination, frame: frame)
  end

  def folio_action_return_to(fallback:)
    sheet_action_return_to(fallback: fallback)
  end
end
