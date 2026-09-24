# frozen_string_literal: true

module VendorDirectory
  # One redeemable deal at one vendor. `kind` mirrors Dinerzflow's voucher_type
  # so the mock and the eventual API speak the same vocabulary.
  Offer = Data.define(
    :id,
    :vendor_id,
    :title,
    :subtitle,
    :kind,
    :value_label,
    :terms,
    :valid_until,
    :per_guest_limit,
    :remaining
  ) do
    KINDS = %w[percentage fixed free_item].freeze

    def to_param = id

    def expires_on = valid_until && Date.parse(valid_until)

    def expiring_soon?
      return false if expires_on.blank?

      expires_on <= 30.days.from_now.to_date
    end

    def scarce? = remaining.present? && remaining <= 25
  end
end
