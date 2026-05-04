# frozen_string_literal: true

module Admin
  class IntegrationsController < Admin::BaseController
    def show
      @channex_api_key = AppConfig.get("channex_api_key")
      @channex_environment = AppConfig.get("channex_environment") || "staging"

      # Cloudflare R2 Settings
      @r2_access_key_id = AppConfig.get("r2_access_key_id")
      @r2_secret_access_key = AppConfig.get("r2_secret_access_key")
      @r2_bucket = AppConfig.get("r2_bucket")
      @r2_endpoint = AppConfig.get("r2_endpoint")
      @r2_region = AppConfig.get("r2_region") || "auto"
      @r2_public_url = AppConfig.get("r2_public_url")
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

      redirect_to admin_integrations_path, notice: "Settings saved successfully."
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
          render json: { success: false, message: "Bucket name is missing." }, status: :unprocessable_entity
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
  end
end
