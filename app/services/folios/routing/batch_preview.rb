# frozen_string_literal: true

module Folios
  module Routing
    # What a billing-route change would do, before it is applied. `review_required?`
    # decides whether staff are shown the impact screen or the change is applied
    # straight through, so it is the member the offcanvas branches on.
    BatchPreview = ApplicationResult.define(
      :changes, :child_changes, :tax_changes, :impacts,
      :count, :amount, :upcoming_count, :upcoming_amount, :"review_required?"
    )
  end
end
