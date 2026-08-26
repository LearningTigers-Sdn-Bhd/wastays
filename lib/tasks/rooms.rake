namespace :rooms do
  desc "Audit legacy room-number data without changing records"
  task audit_legacy_directory: :environment do
    result = Rooms::AuditLegacyDirectory.new.call

    if result.success?
      puts "Legacy room directory audit passed."
      next
    end

    puts "Legacy room directory audit found #{result.blocking_issues.size} blocking issue(s):"
    result.blocking_issues.each do |issue|
      puts "  [#{issue.code}] Hotel #{issue.hotel_id} (#{issue.hotel_name}), " \
           "room type #{issue.room_type_id} (#{issue.room_type_name}): #{issue.message}"
    end

    exit 1
  end
end
