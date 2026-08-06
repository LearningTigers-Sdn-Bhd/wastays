# frozen_string_literal: true

module HotelPortal
  # The hotel portal is split into layers, each with its own layout, sidebar and
  # navigation helper. Operations is where the day runs, so it is the default
  # layer and the only one that links out to the others.
  #
  # Those links open in a new tab on purpose: reading a report or chasing an
  # invoice is something you do *beside* the front desk, not instead of it, so
  # the working tab stays where it was. That is why entries here are rendered
  # with `external: true` -- the same treatment admin gives its Observation Deck
  # door.
  #
  # Settings is deliberately absent. It is configuration rather than work, and
  # it keeps its long-standing home in the profile menu.
  module LayersHelper
    LAYERS = {
      financials: {
        label: "Financials",
        icon: "landmark",
        route: :hotel_folios_path,
        search_text: "Financials Folios Ledger Accounts Receivable External Accounts Invoices Payment Record Statements Aging Billing Cashiering",
        permission: [ "view_bookings", "view_reports", "manage_corporate_accounts" ]
      }
    }.freeze

    # A nav row in the operations sidebar pointing at another layer's landing
    # page. Permission is the union of what the target layer can show, so the
    # door only appears when there is something behind it.
    def hotel_layer_nav_item(key)
      layer = LAYERS.fetch(key)

      PanelsUI::Navigation::Item.new(
        label: layer[:label],
        path: public_send(layer[:route], current_hotel),
        icon: layer[:icon],
        search_text: layer[:search_text],
        permission: layer[:permission],
        external: true
      )
    end
  end
end
