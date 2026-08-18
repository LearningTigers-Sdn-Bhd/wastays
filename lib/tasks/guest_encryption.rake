namespace :guest_encryption do
  desc "Report guests whose encrypted email/phone/government_id can't be decrypted with the current key (dry run by default; FIX=true clears them)"
  task audit: :environment do
    fix = ActiveModel::Type::Boolean.new.cast(ENV["FIX"])
    columns = %w[email phone government_id]

    total = Guest.count
    puts "Scanning #{total} guest(s)#{" (FIX=true: clearing unreadable fields)" if fix}..."

    unreadable = Hash.new { |h, k| h[k] = [] }

    Guest.find_each do |guest|
      columns.each do |column|
        raw = guest.read_attribute_before_type_cast(column)
        next if raw.blank?
        next unless envelope_like?(raw)

        begin
          ActiveRecord::Encryption.encryptor.decrypt(raw)
        rescue ActiveRecord::Encryption::Errors::Base, JSON::ParserError, ArgumentError => e
          unreadable[column] << guest.id
          print "x"

          if fix
            Guest.where(id: guest.id).update_all(column => nil, updated_at: Time.current)
          end
          next
        end
        print "."
      end
    end

    puts "\n\nUnreadable fields by column:"
    columns.each do |column|
      ids = unreadable[column]
      puts "  #{column}: #{ids.size} guest(s)#{ids.any? ? " (#{ids.first(20).join(', ')}#{ids.size > 20 ? ", ..." : ""})" : ""}"
    end

    if fix
      puts "\nCleared unreadable fields above -- affected guests will be asked to resupply this data on their next booking."
    elsif unreadable.values.any?(&:present?)
      puts "\nDry run only. Re-run with FIX=true to clear the unreadable fields (guests will resupply the data on their next booking)."
    end
  end

  def envelope_like?(text)
    text = text.to_s
    text.start_with?("{\"p\":", "{\"p\"=>", "{\"ct\":", "{\"iv\":") || text.include?("\"_rails\"") || text.include?("\"ciphertext\"")
  end
end
