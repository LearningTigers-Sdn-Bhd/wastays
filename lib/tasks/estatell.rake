namespace :estatell do
  desc "Read-only export of one hotel for the estatell importer: bin/rails \"estatell:export[3]\" (ESTATELL_EXPORT_DIR=dir saves locally instead of R2)"
  task :export, [ :hotel_id ] => :environment do |_task, args|
    hotel = Hotel.find_by(id: args[:hotel_id]) if args[:hotel_id].present?
    abort "Hotel not found: #{args[:hotel_id].inspect}. Usage: bin/rails \"estatell:export[hotel_id]\"" unless hotel

    result = EstatellExports::ExportHotel.call(hotel: hotel, output_dir: ENV["ESTATELL_EXPORT_DIR"])
    puts "Key:    #{result.key}"
    puts "Saved:  #{result.path}" if result.path
    puts "SHA256: #{result.sha256}"
  rescue EstatellExports::ExportHotel::Error => e
    abort "Export failed: #{e.message}"
  end
end
