if Rails.env.development? || Rails.env.test?
  encryption_defaults = {
    primary_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "7b5a3a5d35c94a27d7ad9f2c3b2e8c81"),
    deterministic_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", "d1c5a8a8f5c245e4b1a7cba834dfffc2"),
    key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", "a3e2f69d9b0f4d8fb5c2a7c3d6f1e789")
  }

  Rails.application.config.active_record.encryption.primary_key ||= encryption_defaults[:primary_key]
  Rails.application.config.active_record.encryption.deterministic_key ||= encryption_defaults[:deterministic_key]
  Rails.application.config.active_record.encryption.key_derivation_salt ||= encryption_defaults[:key_derivation_salt]
end
