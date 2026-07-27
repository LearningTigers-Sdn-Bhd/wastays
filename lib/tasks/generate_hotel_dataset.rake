# frozen_string_literal: true

namespace :hotel_generator do
  desc "Generates a programmatically isolated fictional hotel with a complete booking ecosystem"
  task run: :environment do
    require "securerandom"
    require "faker"

    puts "\n========================================================================"
    puts "             WAStays Fictional Hotel & Dataset Generator"
    puts "========================================================================"

    # Wrap everything in a transaction for safety
    ActiveRecord::Base.transaction do
      # 1. Create a programmatically isolated Account
      puts "\n-> Creating a new isolated Account..."
      account_suffix = SecureRandom.hex(4)
      account = Account.create!(
        name: "Sabah Heritage Hotels (#{account_suffix})",
        status: "active"
      )
      puts "   Account Created: ID #{account.id} | Slug: #{account.slug}"

      # 2. Create the Boutique Hotel
      puts "\n-> Creating a new Boutique Hotel..."
      hotel = Hotel.create!(
        account: account,
        name: "Jesselton Rainforest Lodge",
        address: "Mile 10, Kinabalu National Park Road",
        city: "Kundasang",
        country: "Malaysia",
        status: "live",
        star_rating: 4,
        default_currency: "MYR",
        preferred_channel_manager: "channex",
        hotel_prefix: "JRL",
        time_zone: "Kuala Lumpur",
        contact_phone: "+6088234567",
        contact_email: "info@jesseltonrainforest.com",
        whatsapp_number: "+6088234567",
        business_starts_at: "08:00:00",
        business_ends_at: "02:00:00",
        arrival_grace_period: 7200,
        sst_enabled: true,
        tourism_tax_enabled: true,
        tourism_tax_amount: 10.0
      )
      puts "   Hotel Created: ID #{hotel.id} | Prefix: #{hotel.hotel_prefix}"
      transaction_codes = TransactionCodes::Resolver.for(hotel)

      # Create Property Policy
      PropertyPolicy.create!(
        hotel: hotel,
        check_in_time: "14:00",
        check_out_time: "12:00"
      )
      puts "   Property Policy created (Check-in: 14:00, Check-out: 12:00)"

      # 3. Create Manager User
      puts "\n-> Creating Manager User..."
      owner_role = Role.find_or_create_by!(account: account, slug: "hotel_owner") { |r| r.name = "Hotel Owner" }
      user = User.create!(
        name: "Lodge Manager",
        email: "manager_#{account_suffix}@jesseltonrainforest.com",
        role: "admin",
        account: account,
        password: "password123",
        password_confirmation: "password123",
        time_zone: "Kuala Lumpur"
      )
      UserHotelAccess.create!(user: user, hotel: hotel, role: owner_role)
      puts "   User Created: #{user.email} (Password: password123)"

      # Get room amenities from list
      available_room_amenities = Amenity.room.pluck(:slug) rescue []
      selected_amenities = available_room_amenities.sample(4)

      # 4. Create Room Types
      puts "\n-> Creating Room Types..."
      standard_type = RoomType.create!(
        hotel: hotel,
        name: "Standard Room",
        description: "Cozy standard room with mountain view.",
        quantity: 12,
        base_price: 150.0,
        max_adults: 2,
        max_children: 1,
        room_number_mode: "custom",
        room_numbers: (101..112).map(&:to_s),
        amenities: selected_amenities
      )
      puts "   Room Type: Standard Room created (12 rooms, 101-112)"

      deluxe_type = RoomType.create!(
        hotel: hotel,
        name: "Deluxe Room",
        description: "Spacious room with king bed and balcony.",
        quantity: 12,
        base_price: 250.0,
        max_adults: 2,
        max_children: 2,
        room_number_mode: "custom",
        room_numbers: (201..212).map(&:to_s),
        amenities: selected_amenities
      )
      puts "   Room Type: Deluxe Room created (12 rooms, 201-212)"

      suite_type = RoomType.create!(
        hotel: hotel,
        name: "Executive Suite",
        description: "Luxury suite with private lounge and hot tub.",
        quantity: 6,
        base_price: 450.0,
        max_adults: 3,
        max_children: 2,
        room_number_mode: "custom",
        room_numbers: (301..306).map(&:to_s),
        amenities: selected_amenities
      )
      puts "   Room Type: Executive Suite created (6 rooms, 301-306)"

      # 5. Create Rate Plans
      puts "\n-> Creating Rate Plans..."
      standard_plan = hotel.rate_plans.find_by!(name: "Standard Rate")

      walk_in_plan = hotel.rate_plans.create!(
        name: "Walk-in Rate",
        sell_mode: "per_room",
        currency: "MYR"
      )

      corporate_plan = hotel.rate_plans.create!(
        name: "Corporate Rate",
        sell_mode: "per_room",
        currency: "MYR"
      )

      # Associate room types with new rate plans
      [ standard_type, deluxe_type, suite_type ].each do |rt|
        rt.room_type_rate_plans.find_or_create_by!(rate_plan: walk_in_plan)
        rt.room_type_rate_plans.find_or_create_by!(rate_plan: corporate_plan)
      end
      puts "   Standard Rate, Walk-in Rate, and Corporate Rate plans associated."

      # 6. Populate Rates and Availability matrix (from -30 to +90 days)
      puts "\n-> Populating Rates and Availability Matrix (-30 to +90 days)..."
      date_range = (Date.current - 30.days..Date.current + 90.days).to_a

      Thread.current[:skip_ari_sync] = true
      begin
        [ standard_type, deluxe_type, suite_type ].each do |rt|
          # Populate inventories
          date_range.each do |date|
            RoomInventory.create!(
              room_type: rt,
              date: date,
              quantity: rt.quantity,
              status: "open",
              available_room_numbers: rt.room_numbers
            )
          end

          # Populate rates
          rt.rate_plans.each do |rp|
            date_range.each do |date|
              is_weekend = date.friday? || date.saturday?
              multiplier = is_weekend ? 1.2 : 1.0

              if rp.name == "Walk-in Rate"
                multiplier *= 1.1
              elsif rp.name == "Corporate Rate"
                multiplier *= 0.85
              end

              price = (rt.base_price * multiplier).round(2)

              RoomRate.create!(
                room_type: rt,
                rate_plan: rp,
                date: date,
                price: price,
                currency: "MYR",
                walk_in_price: (price * 1.1).round(2),
                corporate_price: (price * 0.85).round(2)
              )
            end
          end
        end
      ensure
        Thread.current[:skip_ari_sync] = nil
      end
      puts "   Rates & Inventories successfully generated."

      # 7. Generate a unique pool of 55 Guests
      puts "\n-> Generating 55 Guest Profiles..."
      guest_pool = []
      countries = [
        "Malaysia", "Malaysia", "Malaysia", "Singapore", "Japan",
        "South Korea", "United Kingdom", "Australia", "Indonesia", "China"
      ]
      genders = [ "male", "female", "other" ]

      55.times do |i|
        name = "#{Faker::Name.first_name} #{Faker::Name.last_name} (#{i + 1})"
        email = "guest_#{i + 1}_#{SecureRandom.hex(3)}@jrl-test.com"
        phone = "+601#{rand(10000000..99999999)}"
        country = countries.sample
        gender = genders.sample
        doc_type = country == "Malaysia" ? "ic" : "passport"
        gov_id = doc_type == "ic" ? "#{rand(70..99)}0101-#{rand(10..14)}-#{rand(1000..9999)}" : "P#{rand(10000000..99999999)}"

        guest = Guest.create!(
          name: name,
          email: email,
          phone: phone,
          country: country,
          gender: gender,
          document_type: doc_type,
          government_id: gov_id,
          created_by_hotel: hotel
        )
        guest_pool << guest
      end
      puts "   55 Guest Profiles created successfully."

      # 8. Create Bookings schedule to avoid overlaps
      puts "\n-> Seeding bookings schedule..."

      # Select 12 room numbers to distribute bookings across
      rooms_to_use = [
        { type: standard_type, num: "101" },
        { type: standard_type, num: "102" },
        { type: standard_type, num: "103" },
        { type: standard_type, num: "104" },
        { type: deluxe_type, num: "201" },
        { type: deluxe_type, num: "202" },
        { type: deluxe_type, num: "203" },
        { type: deluxe_type, num: "204" },
        { type: suite_type, num: "301" },
        { type: suite_type, num: "302" },
        { type: suite_type, num: "303" },
        { type: suite_type, num: "304" }
      ]

      today = Date.current
      bookings_count = 0
      bookings_by_status = Hash.new(0)

      # Loop rooms
      rooms_to_use.each_with_index do |room_data, room_idx|
        rt = room_data[:type]
        room_num = room_data[:num]

        # Standard Rate is primary, Walk-in for room_idx 1, 5, 9, Corporate for room_idx 2, 6, 10
        rate_plan = if room_idx % 4 == 1
                      walk_in_plan
        elsif room_idx % 4 == 2
                      corporate_plan
        else
                      standard_plan
        end

        # Define 8 stay templates for each room
        stay_templates = [
          # Past Stays
          { check_in: today - 25.days, check_out: today - 21.days, status: "completed" },
          { check_in: today - 15.days, check_out: today - 11.days, status: "completed" },

          # Active Stay (1 active stay per room, distributed status)
          case room_idx % 4
          when 0
            { check_in: today - 2.days, check_out: today + 2.days, status: "checked_in" } # In-House
          when 1
            { check_in: today - 3.days, check_out: today, status: "checked_in" } # Checking Out Today
          when 2
            { check_in: today, check_out: today + 3.days, status: "confirmed" } # Arriving Today
          when 3
            { check_in: today - 2.days, check_out: today + 1.day, status: "checked_in" } # Checking Out Tomorrow
          end,

          # Future Bookings
          { check_in: today + 4.days, check_out: today + 8.days, status: "confirmed" },
          { check_in: today + 12.days, check_out: today + 16.days, status: "confirmed" },
          { check_in: today + 22.days, check_out: today + 27.days, status: "confirmed" },
          { check_in: today + 35.days, check_out: today + 41.days, status: "confirmed" },
          { check_in: today + 50.days, check_out: today + 56.days, status: "confirmed" }
        ].compact

        stay_templates.each do |tmpl|
          check_in = tmpl[:check_in]
          check_out = tmpl[:check_out]
          status = tmpl[:status]

          # Assign guests sequentially, causing wraps and repeat guests
          guest = guest_pool[bookings_count % guest_pool.size]

          # Build financial snapshot using the system's service
          snapshot = Bookings::BuildFinancialSnapshot.new(
            hotel: hotel,
            check_in: check_in,
            check_out: check_out,
            guest_country: guest.country,
            room_type: rt,
            rate_plan: rate_plan,
            quantity: 1
          ).call

          total_amount = snapshot.room_total + snapshot.tax_total
          tourism_tax_item = snapshot.tax_lines.find { |t| t["type"] == "tourism_tax" }
          tourism_tax_amount = tourism_tax_item ? tourism_tax_item["amount"].to_d : 0.to_d

          # Create Booking
          booking = hotel.bookings.create!(
            check_in: check_in,
            check_out: check_out,
            guest_name: guest.name,
            guest_email: guest.email,
            guest_phone: guest.phone,
            guest_country: guest.country,
            guest_gender: guest.gender,
            guest_document_type: guest.document_type,
            guest_government_id: guest.government_id,
            adults: 2,
            children: 0,
            currency: "MYR",
            status: status,
            payment_status: (status == "completed" || (status == "checked_in" && room_idx % 2 == 0)) ? "captured" : "pending",
            total_amount: total_amount,
            tax_lines: snapshot.tax_lines,
            tax_posting_snapshot: snapshot.tax_posting_snapshot,
            tourism_tax_amount: tourism_tax_amount,
            tourism_tax_applied: tourism_tax_amount.positive?,
            tourism_tax_collected: (status == "completed"),
            source: "internal"
          )

          # Link guest
          booking.booking_guests.create!(guest: guest, is_primary: true)

          # Create BookingRoom
          booking.booking_rooms.create!(
            room_type: rt,
            rate_plan: rate_plan,
            subtotal: snapshot.room_total,
            room_type_snapshot: rt.as_json,
            nightly_rate_snapshot: snapshot.nightly_rate_snapshot,
            room_number: room_num
          )

          # Set margin rates/amounts
          margin_rate = hotel.effective_margin_rate
          margin_amount = (booking.total_amount * (margin_rate / 100.0)).round(2)
          booking.update!(
            margin_rate: margin_rate,
            margin_amount: margin_amount,
            net_amount: booking.total_amount - margin_amount
          )

          # Generate Folio & FolioTransactions
          folio = Folios::Lifecycle::InitializeForBooking.call(
            booking: booking,
            user: nil,
            options: { system_folio_initialization: true, posting_source: "booking_confirmation" },
            lock: false
          )

          # Record Cash Payment transaction if captured
          if booking.payment_status == "captured"
            payment_code = transaction_codes.for_key("cash_payment")
            FolioTransaction.create!(
              booking_folio: folio,
              amount: total_amount,
              transaction_type: "payment",
              category: "cash",
              posting_date: check_in,
              description: "Cash Payment",
              currency: booking.currency,
              transaction_code: payment_code
            )

            booking.payment_transactions.create!(
              gateway: "manual",
              payment_method: "cash",
              amount_subunits: (total_amount * 100).to_i,
              currency: booking.currency,
              status: "captured",
              captured_at: check_in.to_time + 14.hours,
              event_source: "manual_booking"
            )
          end

          # Create FolioTransactions for nightly charges (only up to Date.current)
          nights = (check_out - check_in).to_i
          (check_in...check_out).each do |date|
            next if date > Date.current

            nightly_room = (snapshot.room_total / nights).round(2)
            nightly_tax = (snapshot.tax_total / nights).round(2)

            room_code = transaction_codes.room_revenue
            FolioTransaction.create!(
              booking_folio: folio,
              amount: nightly_room,
              transaction_type: "charge",
              category: "accommodation",
              posting_date: date,
              description: "Room Charge - #{date}",
              currency: booking.currency,
              transaction_code: room_code
            )

            next if nightly_tax.zero?
            snapshot.tax_lines.each do |tax_line|
              tax_amount = (tax_line["amount"].to_d / nights).round(2)
              next if tax_amount.zero?

              tax_code = transaction_codes.for_tax_type(tax_line["type"])

              FolioTransaction.create!(
                booking_folio: folio,
                amount: tax_amount,
                transaction_type: "charge",
                category: "tax",
                posting_date: date,
                description: "Tax: #{tax_line['name'] || tax_line[:name]} - #{date}",
                currency: booking.currency,
                transaction_code: tax_code,
                metadata: { tax_line: tax_line }
              )
            end
          end

          # Increment counts
          bookings_count += 1
          bookings_by_status[status] += 1
        end
      end

      # 9. Clean console output report
      puts "\n========================================================================"
      puts "            GENERATION COMPLETED SUCCESSFULLY (TRANSACTION COMMITTED)"
      puts "========================================================================"
      puts "Hotel ID:                 #{hotel.id}"
      puts "Hotel Name:               #{hotel.name}"
      puts "Hotel Prefix:             #{hotel.hotel_prefix}"
      puts "Total Rooms Generated:    #{hotel.room_types.sum(:quantity)}"
      puts "Total Guest Profiles:     #{Guest.where(created_by_hotel: hotel).count}"
      puts "Total Bookings Loaded:    #{bookings_count}"
      puts "------------------------------------------------------------------------"
      puts "Breakdown of Bookings by Status/Category:"
      puts "  - Checked In (In-House):          #{bookings_by_status['checked_in']}"
      puts "  - Confirmed (Arriving/Future):   #{bookings_by_status['confirmed']}"
      puts "  - Completed (Past Stays):         #{bookings_by_status['completed']}"
      puts "========================================================================"
    end
  end
end
