# frozen_string_literal: true

module Onboarding
  class ResetTrainingDataJob < ApplicationJob
    queue_as :default

    def perform(hotel_id, actor_id)
      hotel = Hotel.find_by(id: hotel_id)
      return unless hotel

      actor = User.find_by(id: actor_id)
      ResetOperationalData.call(hotel:, actor:)
    end
  end
end
