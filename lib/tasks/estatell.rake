namespace :estatell do
  desc "Read-only export of one hotel for the estatell importer: bin/rails \"estatell:export[3]\""
  task :export, [ :hotel_id ] => :environment do |_task, args|
    hotel = Hotel.find_by(id: args[:hotel_id]) if args[:hotel_id].present?
    abort "Hotel not found: #{args[:hotel_id].inspect}. Usage: bin/rails \"estatell:export[hotel_id]\"" unless hotel

    result = EstatellExports::ExportHotel.call(hotel: hotel)
    puts "Key:    #{result.key}"
    puts "SHA256: #{result.sha256}"
  rescue EstatellExports::ExportHotel::Error => e
    abort "Export failed: #{e.message}"
  end
end
