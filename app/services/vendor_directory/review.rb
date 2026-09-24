# frozen_string_literal: true

module VendorDirectory
  # A guest's rating and comment on a vendor. Two sources feed the same shape:
  # MockAdapter seeds a handful per vendor from config/vendor_directory/mock.yml
  # (standing in for reviews a real backend would already hold), and
  # Concierge::ReviewBook wraps a guest's own session-submitted ones the same
  # way -- so the vendor page can treat both as one list without caring which
  # is which.
  Review = Data.define(:guest_name, :rating, :comment, :posted_at) do
    def rating_i = rating.to_i
  end
end
