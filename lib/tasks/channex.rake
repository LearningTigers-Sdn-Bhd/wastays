namespace :channex do
  desc "Fetch and sync bookings from Channex for all properties or a specific hotel_id"
  task sync_bookings: :environment do
    hotel_id = ENV["HOTEL_ID"]

    hotels = if hotel_id
      [ Hotel.find(hotel_id) ]
    else
      Hotel.where.not(preferred_channel_manager: [ nil, "" ])
    end

    puts "Starting Channex Booking Sync for #{hotels.count} hotel(s)..."

    hotels.each do |hotel|
      puts "Syncing #{hotel.name} (ID: #{hotel.id})..."
      service = ChannelManagers::FetchBookingsService.new(hotel: hotel)
      result = service.call

      if result.success?
        puts "  SUCCESS: #{result.message}"
      else
        puts "  FAILED: #{result.message}"
      end
    end

    puts "Sync complete."
  end

  desc "Run the recurring pull revisions job manually"
  task pull_revisions: :environment do
    puts "Enqueuing ChannelManagers::PullRevisionsJob..."
    ChannelManagers::PullRevisionsJob.perform_now
    puts "Done."
  end
end
