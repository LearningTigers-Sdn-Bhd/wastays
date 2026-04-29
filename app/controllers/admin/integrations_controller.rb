# frozen_string_literal: true

module Admin
  class IntegrationsController < Admin::BaseController
    def show
      @channex_api_key = AppConfig.get("channex_api_key")
      @channex_environment = AppConfig.get("channex_environment") || "staging"
    end

    def update
      if params[:channex_api_key].present?
        AppConfig.set("channex_api_key", params[:channex_api_key].to_s.strip)
      end

      if params[:channex_environment].present?
        AppConfig.set("channex_environment", params[:channex_environment].to_s.strip)
      end

      redirect_to admin_integrations_path, notice: "Channel manager settings saved successfully."
    end
  end
end
