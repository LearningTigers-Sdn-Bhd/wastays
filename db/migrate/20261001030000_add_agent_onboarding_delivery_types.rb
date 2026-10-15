# frozen_string_literal: true

class AddAgentOnboardingDeliveryTypes < ActiveRecord::Migration[8.0]
  OLD_TYPES = %w[
    staff_invitation corporate_invitation admin_submitted
    owner_changes_requested owner_approved owner_launch_decision_required
  ].freeze
  AGENT_TYPES = %w[agent_approved].freeze

  def up
    replace_constraint(OLD_TYPES + AGENT_TYPES)
  end

  def down
    execute "DELETE FROM onboarding_deliveries WHERE delivery_type IN (#{AGENT_TYPES.map { |type| connection.quote(type) }.join(', ')})"
    replace_constraint(OLD_TYPES)
  end

  private

  def replace_constraint(types)
    remove_check_constraint :onboarding_deliveries, name: "onboarding_deliveries_type_allowed"
    add_check_constraint :onboarding_deliveries,
                         "delivery_type IN (#{types.map { |type| connection.quote(type) }.join(', ')})",
                         name: "onboarding_deliveries_type_allowed"
  end
end
