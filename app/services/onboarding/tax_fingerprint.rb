# frozen_string_literal: true

module Onboarding
  # A digest of the tax treatment room revenue currently carries.
  #
  # Room revenue is completed against a particular set of taxes. If those taxes
  # later change the section's answer is stale, but the rule keys alone do not
  # say so — disabling an assigned tax, or changing its amount or rate type,
  # changes what a room night costs while the key set stays identical. So the
  # digest covers the material state of each assigned tax, not just its identity.
  #
  # Taxes the hotel has but has not assigned to room revenue are deliberately
  # absent: editing an unassigned fee does not invalidate anything.
  class TaxFingerprint
    def self.call(hotel) = new(hotel).call

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      Digest::SHA256.hexdigest(descriptors.to_json)
    end

    private

    def descriptors
      room_revenue_code = TransactionCodes::Resolver.for(@hotel).room_revenue
      return [] if room_revenue_code.blank?

      room_revenue_code.transaction_code_taxes.map do |rule|
        [ rule.tax_rule_key, rule.enabled_for_posting?, rule.rate_type, rule.amount.to_s ]
      end.sort
    end
  end
end
