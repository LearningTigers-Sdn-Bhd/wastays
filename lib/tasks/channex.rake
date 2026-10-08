namespace :channex do
  desc "Fetch and sync bookings from Channex for all properties or a specific hotel_id"
  task sync_bookings: :environment do
    hotel_id = ENV["HOTEL_ID"]

    hotels = if hotel_id
      [ Hotel.find(hotel_id) ]
    else
      Hotel.where(preferred_channel_manager: ChannelManagers::SyncOrchestrator::ADAPTERS.keys)
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

  desc "Replay bookings created since an outage longer than 30 min (HOTEL_ID=1 SINCE=2026-10-07T20:00:00Z)"
  task recover_bookings: :environment do
    hotel = Hotel.find(ENV.fetch("HOTEL_ID") { abort "HOTEL_ID is required" })
    since = Time.zone.parse(ENV.fetch("SINCE") { abort "SINCE is required, e.g. 2026-10-07T20:00:00Z" }) ||
      abort("SINCE could not be parsed")

    result = ChannelManagers::RecoverBookingsService.new(hotel: hotel, since: since).call
    puts result.message
    exit(1) unless result.success?
  end
end
