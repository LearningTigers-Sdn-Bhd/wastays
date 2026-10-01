# frozen_string_literal: true

module AgentPortal
  module Hotels
    # The admin create form with the platform choices fixed. An agent enters
    # only the owner and how the hotel sells rooms. The server sets every
    # other value, so a changed request cannot pick a plan or a feature.
    class CreateForm < Admin::Hotels::CreateForm
      AGENT_FIELDS = %i[account_name owner_name owner_email hotel_name sell_mode].freeze
      PLAN_SLUG = "enterprise"

      def initialize(attributes = {})
        super(attributes.to_h.symbolize_keys.slice(*AGENT_FIELDS))
        self.plan_id = Plan.active.find_by(slug: PLAN_SLUG)&.id
        self.preferred_channel_manager = "undecided"
        self.creation_action = "create_only"
        self.verify_owner_account = true
        self.allow_boat_information = false
        self.hide_payout_reports = true
      end
    end
  end
end
