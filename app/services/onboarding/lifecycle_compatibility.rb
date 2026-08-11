# frozen_string_literal: true

module Onboarding
  class LifecycleCompatibility
    LEGACY_SETUP_STATUSES = %w[registered email_verified profile_incomplete rooms_incomplete inventory_incomplete].freeze

    def self.canonical_status(status)
      case status.to_s
      when *LEGACY_SETUP_STATUSES then "setup"
      when "approved" then "live"
      else status.to_s
      end
    end
  end
end
