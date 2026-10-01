# frozen_string_literal: true

module SuperAgents
  # The platform choices for every hotel a super agent brings in, whether the
  # agent creates it or the owner registers from the agent's invite link.
  class HotelDefaults
    PLAN_SLUG = "enterprise"

    def self.call
      {
        plan_id: Plan.active.find_by(slug: PLAN_SLUG)&.id,
        preferred_channel_manager: "undecided",
        allow_boat_information: false,
        hide_payout_reports: true
      }
    end
  end
end
