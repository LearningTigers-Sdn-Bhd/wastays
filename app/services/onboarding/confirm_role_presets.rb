# frozen_string_literal: true

module Onboarding
  class ConfirmRolePresets
    Result = ApplicationResult.define(:section)
    PRESET_SLUGS = %w[hotel_owner general_manager front_desk housekeeper].freeze

    def self.permission_fingerprint(roles)
      ordered = roles.sort_by { |role| PRESET_SLUGS.index(role.slug) }
      Digest::SHA256.hexdigest(ordered.to_h { |role| [ role.slug, role.permissions.map(&:slug).sort ] }.to_json)
    end

    def initialize(hotel:, actor:, confirmed:)
      @hotel = hotel
      @actor = actor
      @confirmed = ActiveModel::Type::Boolean.new.cast(confirmed)
    end

    def call
      HotelOps::SeedAccountRoles.call(@hotel.account)
      return Result.failure("Confirm that you reviewed the preset roles.", section: section) unless @confirmed
      return Result.failure("All four preset roles must be available before continuing.", section: section) unless roles.size == PRESET_SLUGS.size

      result = UpdateSection.new(
        hotel: @hotel,
        section_key: "roles_permissions",
        state: "complete",
        actor: @actor,
        metadata: {
          source: "role_preset_review",
          confirmed_role_slugs: roles.map(&:slug),
          permission_fingerprint: permission_fingerprint
        }
      ).call
      return Result.failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section)
    end

    private

    def roles
      @roles ||= @hotel.account.roles.where(slug: PRESET_SLUGS).includes(:permissions).sort_by { |role| PRESET_SLUGS.index(role.slug) }
    end

    def permission_fingerprint
      self.class.permission_fingerprint(roles)
    end

    def section
      @hotel.onboarding_sections.find_by(section_key: "roles_permissions")
    end
  end
end
