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

  desc "Compare the room directory against the legacy room-number lists"
  task reconcile_directory: :environment do
    total_issues = 0

    Hotel.order(:id).find_each do |hotel|
      result = Rooms::ReconcileDirectory.call(hotel: hotel)
      next if result.reconciled?

      total_issues += result.issues.size
      puts "Hotel #{hotel.id} (#{hotel.name}) has #{result.issues.size} difference(s):"
      result.issues.each { |issue| puts "  [#{issue.type}] #{issue.message}" }
    end

    if total_issues.zero?
      puts "Room directory reconciliation passed."
      next
    end

    puts "Room directory reconciliation found #{total_issues} difference(s)."
    exit 1
  end
end
