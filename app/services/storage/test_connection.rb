# frozen_string_literal: true

module Storage
  # Checks that the stored Cloudflare R2 settings reach the bucket.
  #
  # It lists one object. A reply proves the endpoint resolves, the keys are
  # accepted, and the bucket exists. That is all an admin needs before saving
  # the settings.
  class TestConnection
    Result = Struct.new(:success, :message, keyword_init: true) do
      def success? = success
    end

    # An admin often pastes the bucket URL rather than the account host. The S3
    # client wants the host on its own, so the bucket comes off the end.
    #
    # Both the save and the test use this, so a pasted bucket URL behaves the
    # same way in each.
    def self.normalize_endpoint(endpoint, bucket)
      endpoint = endpoint.to_s.strip
      bucket = bucket.to_s.strip
      return endpoint if bucket.blank?

      endpoint.delete_suffix("/#{bucket}")
    end

    def initialize(access_key_id: nil, secret_access_key: nil, bucket: nil, endpoint: nil, region: nil)
      @access_key_id = value(access_key_id, "r2_access_key_id")
      @secret_access_key = value(secret_access_key, "r2_secret_access_key")
      @bucket = value(bucket, "r2_bucket")
      @endpoint = self.class.normalize_endpoint(value(endpoint, "r2_endpoint"), @bucket)
      @region = value(region, "r2_region").presence || "auto"
    end

    def call
      return failure("Bucket name is missing.") if @bucket.blank?
      return failure("Endpoint URL is missing.") if @endpoint.blank?
      return failure("Access key ID is missing.") if @access_key_id.blank?
      return failure("Secret access key is missing.") if @secret_access_key.blank?

      client.list_objects_v2(bucket: @bucket, max_keys: 1)
      success("Connected to the R2 bucket #{@bucket}.")
    rescue Aws::S3::Errors::ServiceError => e
      failure("Connection failed: #{e.message}")
    rescue StandardError => e
      failure("An error occurred: #{e.message}")
    end

    private

    # A nil argument means the caller said nothing, so fall back to the saved
    # value. An empty argument means the form field is empty, and the test must
    # report that rather than quietly pass on a stored value.
    def value(given, config_key)
      (given.nil? ? AppConfig.get(config_key) : given).to_s.strip
    end

    def client
      Aws::S3::Client.new(
        access_key_id: @access_key_id,
        secret_access_key: @secret_access_key,
        region: @region,
        endpoint: @endpoint,
        force_path_style: true
      )
    end

    def success(message) = Result.new(success: true, message: message)
    def failure(message) = Result.new(success: false, message: message)
  end
end
