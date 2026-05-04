# frozen_string_literal: true

require "active_storage/service/s3_service"

module ActiveStorage
  class Service::R2Service < Service::S3Service
    def initialize(**config)
      # We still call super to initialize standard Active Storage behaviors
      super(**config)
    end

    def client
      # S3Service uses Aws::S3::Resource.new
      @dynamic_client ||= Aws::S3::Resource.new(**s3_options)
    end

    def bucket
      # Dynamically fetch bucket name from database, fallback to config
      current_bucket_name = AppConfig.get("r2_bucket") || @config[:bucket]
      client.bucket(current_bucket_name)
    end

    def url(key, expires_in:, filename:, content_type:, disposition:)
      public_url_base = AppConfig.get("r2_public_url")

      if public_url_base.present?
        # If a public URL is configured, we use it for GET requests
        base = public_url_base.delete_suffix("/")
        "#{base}/#{key}"
      else
        # Fallback to standard S3 signed URL
        private_url(key, expires_in: expires_in, filename: filename, disposition: disposition, content_type: content_type)
      end
    end

    def delete(key)
      instrument :delete, key: key do
        begin
          object_for(key).delete
        rescue Aws::S3::Errors::NoSuchKey
          # Ignore if the file is already gone
        end
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        begin
          bucket.objects(prefix: prefix).batch_delete!
        rescue Aws::S3::Errors::NoSuchKey
          # Ignore if prefixes/objects are already gone
        end
      end
    end

    # R2 compatibility: Sometimes R2 fails when Content-MD5 is sent alongside other headers
    # or due to SDK's automatic checksum calculation.
    def upload_with_single_part(key, io, checksum: nil, content_type: nil, content_disposition: nil, custom_metadata: {})
      # We omit content_md5 if it causes issues, but let's try passing it as a standard header or removing it
      # if R2 complains about "one non-default checksum".
      # Many R2 users found that removing content_md5 fixes the issue.
      object_for(key).put(
        body: io,
        content_type: content_type,
        content_disposition: content_disposition,
        metadata: custom_metadata,
        **upload_options
      )
    rescue Aws::S3::Errors::BadDigest
      raise ActiveStorage::IntegrityError
    end

    def upload_with_multipart(key, io, content_type: nil, content_disposition: nil, custom_metadata: {})
      part_size = [ io.size.fdiv(MAXIMUM_UPLOAD_PARTS_COUNT).ceil, MINIMUM_UPLOAD_PART_SIZE ].max

      upload_stream(
        key: key,
        content_type: content_type,
        content_disposition: content_disposition,
        part_size: part_size,
        metadata: custom_metadata,
        **upload_options
      ) do |out|
        IO.copy_stream(io, out)
      end
    end

    private

    def s3_options
      {
        access_key_id: AppConfig.get("r2_access_key_id") || "placeholder",
        secret_access_key: AppConfig.get("r2_secret_access_key") || "placeholder",
        region: AppConfig.get("r2_region") || "auto",
        endpoint: AppConfig.get("r2_endpoint"),
        force_path_style: true
      }.compact
    end

    def object_for(key)
      bucket.object(key)
    end
  end
end
