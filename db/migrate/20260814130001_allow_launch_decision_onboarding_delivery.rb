# frozen_string_literal: true

class AllowLaunchDecisionOnboardingDelivery < ActiveRecord::Migration[8.1]
  NAME = "onboarding_deliveries_type_allowed"
  ORIGINAL_TYPES = %w[
    staff_invitation corporate_invitation admin_submitted
    owner_changes_requested owner_approved
  ].freeze
  TYPES = (ORIGINAL_TYPES + %w[owner_launch_decision_required]).freeze

  def up
    replace_constraint(TYPES)
  end

  def down
    replace_constraint(ORIGINAL_TYPES)
  end

  private

  def replace_constraint(types)
    remove_check_constraint :onboarding_deliveries, name: NAME
    allowed = types.map { |type| connection.quote(type) }.join(", ")
    add_check_constraint :onboarding_deliveries, "delivery_type IN (#{allowed})", name: NAME
  end
end
