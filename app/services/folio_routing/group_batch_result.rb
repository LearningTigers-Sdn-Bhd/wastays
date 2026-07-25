# frozen_string_literal: true

module FolioRouting
  # A group batch applies the same routes across sibling bookings, so it also
  # reports which bookings it actually touched.
  GroupBatchResult = ApplicationResult.define(:transactions, :touched_booking_ids)
end
