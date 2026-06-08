find_hotel_for_task = lambda do |hotel_name, usage|
  if hotel_name.blank?
    puts "Error: Please provide a hotel name. Usage: #{usage}"
    next nil
  end

  hotel = Hotel.where("name ILIKE ?", hotel_name).first
  if hotel.nil?
    puts "Error: Hotel '#{hotel_name}' not found."
    next nil
  end

  hotel
end

confirm_destructive_countdown = lambda do
  puts "Starting in 5 seconds... (Press Ctrl+C to abort)"
  5.times do |i|
    print "#{5 - i}... "
    sleep 1
  end
  puts "\nProceeding..."
end

namespace :demo do
  desc "Enqueue embeddings for all knowledge documents with pending status"
  task embeddings: :environment do
    Hotel.find_each do |hotel|
      next unless hotel.ai_concierge_enabled?

      pending_docs = hotel.knowledge_documents.where(embedding_status: "pending")
      next if pending_docs.none?

      pending_docs.find_each do |doc|
        HotelKnowledges::GenerateEmbeddingsJob.perform_later(doc.id)
      end
      puts "Enqueued #{pending_docs.count} embedding jobs for hotel #{hotel.id}"
    end
  end

  desc "Delete all AI Concierge data for a specific hotel (prospects and their conversation states/messages)"
  task :delete_ai, [ :hotel_name ] => :environment do |_, args|
    hotel = find_hotel_for_task.call(args[:hotel_name], "bin/rake demo:delete_ai['Hotel Name']")
    next unless hotel

    puts "!!! WARNING: This will PERMANENTLY DELETE AI Concierge data for '#{hotel.name}' !!!"
    puts "  - All prospects and their conversation states/messages"
    confirm_destructive_countdown.call

    ActiveRecord::Base.transaction do
      HotelDemoManagement::ResetState.delete_ai_concierge_data(hotel, logger: $stdout)
    end

    puts "\nSUCCESS: AI Concierge data for '#{hotel.name}' has been deleted."
  end

  desc "Reset demo state for a specific hotel (delete bookings/night audits, reset rates/statuses, reseed demo content)"
  task :reset, [ :hotel_name ] => :environment do |_, args|
    hotel = find_hotel_for_task.call(args[:hotel_name], "bin/rake demo:reset['Hotel Name']")
    next unless hotel

    puts "!!! WARNING: This will PERMANENTLY DELETE demo operations data, then reset rates/statuses for '#{hotel.name}' !!!"
    confirm_destructive_countdown.call

    result = HotelDemoManagement::ResetState.new(
      hotel: hotel,
      logger: $stdout,
      embed: ENV["EMBED"] == "true"
    ).call

    unless result.success?
      puts "\nERROR: #{result.error}"
      exit 1
    end

    puts "\nSUCCESS: '#{hotel.name}' has been reset to demo state."
  end

  desc "Reset demo state and seed a realistic day-by-day operations simulation scenario"
  task :realtime, [ :hotel_name ] => :environment do |_, args|
    hotel = find_hotel_for_task.call(args[:hotel_name], "bin/rake demo:realtime['Hotel Name']")
    next unless hotel

    puts "!!! WARNING: This will PERMANENTLY DELETE demo operations data, then reset rates/statuses and simulate operations for '#{hotel.name}' !!!"
    confirm_destructive_countdown.call

    result = HotelDemoManagement::SeedRealtimeScenario.new(
      hotel: hotel,
      logger: $stdout,
      embed: ENV["EMBED"] == "true"
    ).call

    unless result.success?
      puts "\nERROR: #{result.error}"
      exit 1
    end

    puts "\nSUCCESS: '#{hotel.name}' has been reset and realtime scenario loaded."
  end
end
