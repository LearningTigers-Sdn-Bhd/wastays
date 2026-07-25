# frozen_string_literal: true

module Folios
  # Where a charge should land, and why it landed there. The reason travels with
  # the answer because it is written onto the posted transaction's metadata —
  # route_source names the rule that decided (primary_folio, routing_rule,
  # follows_parent, manual_override, selected_folio) and route_metadata carries
  # the evidence for it.
  RouteResult = ApplicationResult.define(:folio, :route_source, :route_metadata)
end
