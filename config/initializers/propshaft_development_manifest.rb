if Rails.env.development?
  # Propshaft uses static resolution whenever a manifest file exists.
  # Removing stale dev manifests keeps asset helpers dynamic and hot-reload friendly.
  manifest_path = Rails.root.join("public/assets/.manifest.json")
  File.delete(manifest_path) if File.exist?(manifest_path)
end
