namespace :app_config do
  desc "Encrypt existing plaintext values in app_configs"
  task encrypt_existing: :environment do
    total = AppConfig.count
    puts "Encrypting #{total} AppConfig row(s)..."

    AppConfig.find_each do |config|
      config.value_will_change!
      config.save!
      print "."
    end

    puts "\nDone. All AppConfig values are now encrypted."
  end
end
