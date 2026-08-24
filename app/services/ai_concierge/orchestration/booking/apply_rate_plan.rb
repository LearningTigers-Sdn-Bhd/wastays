# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Booking
      # Writes a chosen rate plan onto the branch.
      #
      # Two turns reach this: the guest naming a rate plan on its own, and the
      # guest naming it in the same breath as the room. They must leave the
      # branch spelled identically, because what confirmation reads back is the
      # branch and nothing else.
      class ApplyRatePlan
        def initialize(active_branch:, selected_option:, rate_plan:)
          @active_branch = active_branch
          @selected_option = selected_option
          @rate_plan = rate_plan
        end

        def call
          selected_option["selected_rate_plan"] = rate_plan
          active_branch["selected_option"] = selected_option
          active_branch["selected_rate_plan_id"] = rate_plan["rate_plan_id"]
          active_branch["selected_rate_plan_name"] = rate_plan["name"]
          active_branch["confirmation_candidate"] = selected_option
          active_branch
        end

        private

        attr_reader :active_branch, :selected_option, :rate_plan
      end
    end
  end
end
