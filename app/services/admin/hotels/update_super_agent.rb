# frozen_string_literal: true

module Admin::Hotels
  # Links a hotel to a super agent, for hotels that joined before agents
  # existed or without the invite link. The agent becomes the hotel's creator
  # and can open it. A nil agent unlinks. The old agent loses access.
  class UpdateSuperAgent
    def self.call(hotel:, agent:)
      ActiveRecord::Base.transaction do
        previous = hotel.created_by_user
        if previous&.super_agent? && previous != agent
          UserHotelAccess.where(user: previous, hotel: hotel).destroy_all
        end

        hotel.update!(created_by_user: agent)
        SuperAgents::GrantHotelAccess.call(agent: agent, hotel: hotel) if agent
      end
      true
    end
  end
end
