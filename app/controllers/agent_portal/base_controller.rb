# frozen_string_literal: true

module AgentPortal
  # The portal for super agents. An agent creates hotels and opens the hotels
  # they created. Every other page in the app stays closed to them.
  class BaseController < ApplicationController
    layout "agent"

    before_action :authenticate_user!
    before_action :authenticate_super_agent!

    helper AgentPortal::NavigationHelper

    private

    def authenticate_super_agent!
      return if current_user&.super_agent?

      redirect_to root_path, alert: "You are not authorized to access the agent portal."
    end
  end
end
