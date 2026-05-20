namespace :hotel_ops do
  desc "Clean state for a specific hotel (delete bookings/night audits, reset rates to base, recalibrate statuses)"
  task :clean_state, [ :hotel_name ] => :environment do |_, args|
    hotel_name = args[:hotel_name]
    if hotel_name.blank?
      puts "Error: Please provide a hotel name. Usage: bin/rake hotel_ops:clean_state['Hotel Name']"
      exit 1
    end

    hotel = Hotel.where("name ILIKE ?", hotel_name).first

    if hotel.nil?
      puts "Error: Hotel '#{hotel_name}' not found."
      exit 1
    end

    puts "!!! WARNING: This will PERMANENTLY DELETE all bookings and night audits, then reset rates/statuses for '#{hotel.name}' !!!"
    puts "Starting in 5 seconds... (Press Ctrl+C to abort)"
    5.times do |i|
      print "#{5 - i}... "
      sleep 1
    end
    puts "\nProceeding..."

    ActiveRecord::Base.transaction do
      # 1. Recalibrate Business Hours, Policies, and Taxes
      puts "Recalibrating business hours, grace period, amenities, and taxes..."
      hotel.update!(
        time_zone: "Kuala Lumpur",
        business_starts_at: "08:00",
        business_ends_at: "02:00",
        arrival_grace_period: 7200,
        amenities: %w[wifi swimming_pool fitness_center spa_wellness_centre laundry],
        tourism_tax_enabled: true,
        tourism_tax_amount: 10.0,
        sst_enabled: true
      )

      # 1b. Recalibrate Hotel Taxes
      puts "Cleaning and resetting hotel taxes..."
      hotel.hotel_taxes.destroy_all
      hotel.hotel_taxes.create!([
        { name: "Service Tax", rate_type: "percentage", amount: 8.0, enabled: true, foreign_guests_only: false },
        { name: "Service Charge", rate_type: "percentage", amount: 10.0, enabled: true, foreign_guests_only: false }
      ])

      # 2. Clean Night Audits
      night_audit_count = hotel.night_audits.count
      puts "Destroying #{night_audit_count} night audits..."
      hotel.night_audits.destroy_all

      # 2. Clean Bookings
      booking_ids = hotel.bookings.pluck(:id)
      folio_ids = BookingFolio.where(booking_id: booking_ids).pluck(:id)

      puts "Force cleaning #{FolioTransaction.where(booking_folio_id: folio_ids).count} immutable transactions..."
      FolioTransaction.where(booking_folio_id: folio_ids).delete_all

      booking_count = hotel.bookings.count
      puts "Destroying #{booking_count} bookings..."
      hotel.bookings.destroy_all

      # 3. Clean and Recalibrate Rates
      start_date = Date.current
      end_date = Date.new(Date.current.year, 12, 31)

      puts "Recalibrating rates from #{start_date} to #{end_date}..."
      hotel.room_types.each do |room_type|
        # 2a. Ensure Rate Plans exist
        standard_plan = room_type.rate_plans.find_or_create_by!(name: "Standard Rate") do |p|
          p.sell_mode = "per_room"
          p.currency = hotel.default_currency || "MYR"
        end

        non_ref_plan = room_type.rate_plans.find_or_create_by!(name: "Non-Refundable Rate") do |p|
          p.sell_mode = "per_room"
          p.currency = hotel.default_currency || "MYR"
        end

        base_price = room_type.base_price
        puts "  -> Configuring rates for #{room_type.name} (Base: #{base_price})..."

        # 2b. Remove existing rates for this room type in the range
        RoomRate.where(room_type_id: room_type.id, date: start_date..end_date).delete_all

        # 2c. Create new rates for all plans
        rates_to_insert = []
        (start_date..end_date).each do |date|
          # Standard Rate
          rates_to_insert << {
            room_type_id: room_type.id,
            rate_plan_id: standard_plan.id,
            date: date,
            price: base_price,
            currency: standard_plan.currency,
            created_at: Time.current,
            updated_at: Time.current
          }

          # Non-Refundable Rate (10% discount)
          rates_to_insert << {
            room_type_id: room_type.id,
            rate_plan_id: non_ref_plan.id,
            date: date,
            price: (base_price * 0.9).round(2),
            currency: non_ref_plan.currency,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        RoomRate.insert_all(rates_to_insert) if rates_to_insert.any?
      end

      # 4. Recalibrate Room Statuses
      puts "Recalibrating room statuses..."
      hotel.room_types.each do |room_type|
        # Reset all existing statuses to 'ready'
        room_type.room_statuses.update_all(status: "ready", last_changed_at: Time.current, updated_at: Time.current)

        expected_room_numbers = room_type.room_numbers.map(&:to_s)
        existing_statuses = room_type.room_statuses.pluck(:room_number)

        # Create missing
        missing_numbers = expected_room_numbers - existing_statuses
        if missing_numbers.any?
          puts "  -> #{room_type.name}: Adding statuses for #{missing_numbers.join(', ')}"
          missing_numbers.each do |num|
            room_type.room_statuses.create!(
              hotel: hotel,
              room_number: num,
              status: "ready"
            )
          end
        end

        # Remove orphans
        orphan_numbers = existing_statuses - expected_room_numbers
        if orphan_numbers.any?
          puts "  -> #{room_type.name}: Removing orphaned statuses for #{orphan_numbers.join(', ')}"
          room_type.room_statuses.where(room_number: orphan_numbers).destroy_all
        end
      end

      # 5. Trigger Sync if needed
      if hotel.preferred_channel_manager.present?
        puts "Triggering Channel Manager Sync..."
        ChannelManagers::SyncJob.perform_later(hotel.id, start_date, end_date)
      end
    end

    puts "\nSUCCESS: '#{hotel.name}' has been recalibrated to a clean state."
  end
end
