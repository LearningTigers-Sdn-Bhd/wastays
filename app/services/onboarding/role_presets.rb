# frozen_string_literal: true

module Onboarding
  # The four roles every account starts with. This class holds what onboarding
  # needs to know about them: their order, the one-line summary the Team step
  # shows, and the fingerprint that tells us whether their permissions moved
  # after the owner reviewed them.
  class RolePresets
    PRESET_SLUGS = %w[hotel_owner general_manager front_desk housekeeper].freeze

    # Onboarding shows what a role is for, not what it can press. The permission
    # list belongs in Staff Management after launch, where roles can be changed.
    SUMMARIES = {
      "hotel_owner" => "Full control of the account, billing, and every property setting.",
      "general_manager" => "Runs the property day to day. Everything except account and billing.",
      "front_desk" => "Bookings, check-in, guest folios, and payments.",
      "housekeeper" => "Room status and housekeeping tasks only."
    }.freeze

    # Ordered by rank, not by name: the cards read as a hierarchy.
    def self.for(account) = account.roles.where(slug: PRESET_SLUGS).in_order_of(:slug, PRESET_SLUGS)

    def self.summary(slug) = SUMMARIES[slug.to_s]

    def self.permission_fingerprint(roles)
      ordered = roles.sort_by { |role| PRESET_SLUGS.index(role.slug) }
      Digest::SHA256.hexdigest(ordered.to_h { |role| [ role.slug, role.permissions.map(&:slug).sort ] }.to_json)
    end
  end
end
