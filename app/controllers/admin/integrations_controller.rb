# frozen_string_literal: true

module Admin
  class IntegrationsController < Admin::BaseController
    # One entry per tab. The view reads this for both the tab strip and the
    # panels, so a tab and its partial can never drift apart.
    TABS = [
      { name: "channel_manager", label: "Channel manager", icon: "waypoints" },
      { name: "storage", label: "Storage", icon: "database" },
      { name: "ai_providers", label: "AI providers", icon: "sparkles" },
      { name: "around_that", label: "AroundThat", icon: "map-pin" }
    ].freeze

    TAB_NAMES = TABS.map { |tab| tab[:name] }.freeze

    CHANNEX_ENVIRONMENTS = [
      { label: "Staging", value: "staging" },
      { label: "Production", value: "production" }
    ].freeze

    AI_PROVIDERS = [
      { label: "Gemini", key: "gemini_api_key" },
      { label: "OpenAI", key: "openai_api_key" },
      { label: "DeepSeek", key: "deepseek_api_key" },
      { label: "Claude", key: "anthropic_api_key" }
    ].freeze

    AI_PROVIDER_CONFIG_KEYS = AI_PROVIDERS.map { |provider| provider[:key] }.freeze

    AROUND_THAT_CONFIG_KEYS = %w[
      aroundthat_api_key
      aroundthat_base_url
      aroundthat_environment
    ].freeze

    AROUND_THAT_ENVIRONMENTS = [
      { label: "Staging", value: "staging" },
      { label: "Production", value: "production" }
    ].freeze

    def show
      @active_tab = requested_tab

      @channex_api_key = AppConfig.get("channex_api_key")
      @channex_environment = AppConfig.get("channex_environment") || "staging"

      # Cloudflare R2 Settings
      @r2_access_key_id = AppConfig.get("r2_access_key_id")
      @r2_secret_access_key = AppConfig.get("r2_secret_access_key")
      @r2_bucket = AppConfig.get("r2_bucket")
      @r2_endpoint = AppConfig.get("r2_endpoint")
      @r2_region = AppConfig.get("r2_region") || "auto"
      @r2_public_url = AppConfig.get("r2_public_url")

      @ai_provider_keys = AI_PROVIDER_CONFIG_KEYS.index_with { |key| AppConfig.get(key) }

      # AroundThat: the base URL stays a stored value so staging and production
      # can be switched without a deploy.
      @around_that_values = AROUND_THAT_CONFIG_KEYS.index_with { |key| AppConfig.get(key) }
      @around_that_values["aroundthat_environment"] ||= "staging"
    end

    def update
      # Channel Manager Settings
      AppConfig.set("channex_api_key", params[:channex_api_key].to_s.strip) if params[:channex_api_key].present?
      AppConfig.set("channex_environment", params[:channex_environment].to_s.strip) if params[:channex_environment].present?

      # Cloudflare R2 Settings
      bucket_name = params[:r2_bucket].to_s.strip
      endpoint = Storage::TestConnection.normalize_endpoint(params[:r2_endpoint], bucket_name)

      AppConfig.set("r2_access_key_id", params[:r2_access_key_id].to_s.strip) if params.key?(:r2_access_key_id)
      AppConfig.set("r2_secret_access_key", params[:r2_secret_access_key].to_s.strip) if params.key?(:r2_secret_access_key)
      AppConfig.set("r2_bucket", bucket_name) if params.key?(:r2_bucket)
      AppConfig.set("r2_endpoint", endpoint) if params.key?(:r2_endpoint)
      AppConfig.set("r2_region", params[:r2_region].to_s.strip) if params.key?(:r2_region)
      AppConfig.set("r2_public_url", params[:r2_public_url].to_s.strip) if params.key?(:r2_public_url)

      AI_PROVIDER_CONFIG_KEYS.each do |key|
        AppConfig.set(key, params[key].to_s.strip) if params.key?(key)
      end

      # AroundThat Settings
      AROUND_THAT_CONFIG_KEYS.each do |key|
        AppConfig.set(key, params[key].to_s.strip) if params.key?(key)
      end

      # Each form posts the tab it belongs to, so saving does not throw the
      # admin back to the first tab.
      redirect_to admin_integrations_path(tab: requested_tab), notice: "Settings saved successfully."
    end

    # Both tests read the values the form posted, so an admin can try settings
    # before saving them. A field that is absent falls back to the saved value.
    def test_around_that_connection
      render_connection_result(
        AroundThat::TestConnection.new(
          api_key: params[:aroundthat_api_key],
          base_url: params[:aroundthat_base_url],
          environment: params[:aroundthat_environment]
        ).call
      )
    end

    def test_r2_connection
      render_connection_result(
        Storage::TestConnection.new(
          access_key_id: params[:r2_access_key_id],
          secret_access_key: params[:r2_secret_access_key],
          bucket: params[:r2_bucket],
          endpoint: params[:r2_endpoint],
          region: params[:r2_region]
        ).call
      )
    end

    private

    def requested_tab
      TAB_NAMES.include?(params[:tab]) ? params[:tab] : TAB_NAMES.first
    end

    def render_connection_result(result)
      if result.success?
        render json: { success: true, message: result.message }
      else
        render json: { success: false, message: result.message }, status: :unprocessable_content
      end
    end
  end
end
