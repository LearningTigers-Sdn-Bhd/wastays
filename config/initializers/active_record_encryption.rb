if Rails.env.development? || Rails.env.test?
  encryption_config = Rails.application.credentials.active_record_encryption || {}

  Rails.application.config.active_record.encryption.primary_key ||= ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] || encryption_config[:primary_key]
  Rails.application.config.active_record.encryption.deterministic_key ||= ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] || encryption_config[:deterministic_key]
  Rails.application.config.active_record.encryption.key_derivation_salt ||= ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] || encryption_config[:key_derivation_salt]
end
