# frozen_string_literal: true

require "active_storage/service/r2_service"

# Silence AWS metadata service warnings in local development
ENV["AWS_EC2_METADATA_DISABLED"] = "true"

# Define a helper to register additional services
module ActiveStorageServiceRegistry
  def self.inject_services
    storage_config_path = Rails.root.join("config/storage.yml")
    return unless File.exist?(storage_config_path)

    storage_config = YAML.load(ERB.new(File.read(storage_config_path)).result)
    return unless storage_config

    configs = storage_config.deep_symbolize_keys

    # We must ensure ActiveStorage::Blob.services is a hash that includes our services
    # Active Storage 8.0 uses a Registry object, but it can be initialized with configs

    begin
      # If it's already a registry, we can't easily add to it, so we re-create it with all configs
      ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(configs)
    rescue => e
      Rails.logger.error "Failed to register storage services: #{e.message}"
    end
  end
end

# Run the injection after initialization to ensure Rails' own config is loaded
Rails.application.config.after_initialize do
  ActiveStorageServiceRegistry.inject_services
end

# Also run on load just in case
ActiveSupport.on_load(:active_storage_blob) do
  ActiveStorageServiceRegistry.inject_services
end
