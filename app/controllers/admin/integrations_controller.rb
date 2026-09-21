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
      endpoint = params[:r2_endpoint].to_s.strip

      # Sanitize endpoint: If the user pasted the bucket URL (e.g., https://.../bucket-name),
      # strip the bucket name from the end as S3 client expects the base endpoint.
      if bucket_name.present? && endpoint.end_with?("/#{bucket_name}")
        endpoint = endpoint.delete_suffix("/#{bucket_name}")
      end

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

    def test_around_that_connection
      result = AroundThat::TestConnection.new.call

      if result.success?
        render json: { success: true, message: result.message }
      else
        render json: { success: false, message: result.message }, status: :unprocessable_content
      end
    end

    def test_r2_connection
      # We use the service logic to test connection
      begin
        s3_options = {
          access_key_id: AppConfig.get("r2_access_key_id"),
          secret_access_key: AppConfig.get("r2_secret_access_key"),
          region: AppConfig.get("r2_region") || "auto",
          endpoint: AppConfig.get("r2_endpoint"),
          force_path_style: true
        }.compact

        client = Aws::S3::Client.new(**s3_options)
        bucket_name = AppConfig.get("r2_bucket")

        if bucket_name.blank?
          render json: { success: false, message: "Bucket name is missing." }, status: :unprocessable_content
          return
        end

        # Attempt to list objects (limited to 1) to verify connectivity and permissions
        client.list_objects_v2(bucket: bucket_name, max_keys: 1)

        render json: { success: true, message: "Successfully connected to Cloudflare R2 bucket: #{bucket_name}" }
      rescue Aws::S3::Errors::ServiceError => e
        render json: { success: false, message: "Connection failed: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
      end
    end

    private

    def requested_tab
      TAB_NAMES.include?(params[:tab]) ? params[:tab] : TAB_NAMES.first
    end
  end
end
