# frozen_string_literal: true

module Folios
  module Routing
    # The group counterpart of BatchPreview: one entry per sibling booking, plus
    # the totals across all of them.
    GroupBatchPreview = ApplicationResult.define(
      :bookings, :count, :amount, :upcoming_count, :upcoming_amount, :"review_required?"
    )
  end
end
