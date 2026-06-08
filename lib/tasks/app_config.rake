namespace :app_config do
  desc "Encrypt existing plaintext values in app_configs"
  task encrypt_existing: :environment do
    total = AppConfig.count
    puts "Encrypting #{total} AppConfig row(s)..."

    encrypted = 0
    skipped = 0

    AppConfig.find_each do |config|
      raw_value = config.read_attribute_before_type_cast(:value).to_s

      if encrypted_app_config_value?(raw_value)
        skipped += 1
        print "s"
        next
      end

      encrypted_value = AppConfig.type_for_attribute("value").serialize(raw_value)
      quoted_value = AppConfig.connection.quote(encrypted_value)
      quoted_time = AppConfig.connection.quote(Time.current)
      AppConfig.connection.execute(
        "UPDATE app_configs SET value = #{quoted_value}, updated_at = #{quoted_time} WHERE id = #{config.id}"
      )
      encrypted += 1
      print "."
    end

    puts "\nDone. Encrypted #{encrypted} row(s), skipped #{skipped} already encrypted row(s)."
  end

  def encrypted_app_config_value?(raw_value)
    payload = JSON.parse(raw_value)
    payload.is_a?(Hash) && payload.key?("p") && payload.key?("h")
  rescue JSON::ParserError, TypeError
    false
  end
end
