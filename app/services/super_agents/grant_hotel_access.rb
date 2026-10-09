# frozen_string_literal: true

module SuperAgents
  # Lets a super agent open a hotel as General Manager. That is enough to help
  # the owner through onboarding, but not to manage the account. Platform admin
  # controls this access; it is hidden and protected in Staff Management.
  class GrantHotelAccess
    def self.call(agent:, hotel:)
      role = Role.find_by!(account: hotel.account, slug: "general_manager")
      access = UserHotelAccess.find_or_initialize_by(user: agent, hotel: hotel)
      access.update!(role: role, deactivated_at: nil)
      access
    end
  end
end
