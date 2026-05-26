namespace :hotel_ops do
  desc "Migrate existing hotel.faq and hotel.policy JSONB data to hotel_knowledge_documents and chunks"
  task migrate_knowledges: :environment do
    Hotel.find_each do |hotel|
      migrated = 0

      # FAQ sections → one document per section, one chunk per Q&A pair
      Array(hotel.faq).each do |section|
        doc = hotel.knowledge_documents.create!(
          title: section["section_name"].presence || "FAQ",
          source_type: "text",
          category: "faq",
          language: "en",
          embedding_status: "pending",
          tags: [],
          effective_date: nil,
          content: nil
        )
        Array(section["items"]).each_with_index do |item, idx|
          q = item["question"].presence
          a = item["answer"].presence
          content = [ ("Q: #{q}" if q), ("A: #{a}" if a) ].compact.join("\n")
          doc.chunks.create!(content: content, chunk_index: idx) if content.present?
        end
        migrated += 1
      end

      # Policy items → one document per item, one chunk
      Array(hotel.policy).each do |item|
        title = item["title"].presence || "Policy"
        content = [ title, item["content"].presence ].compact.join(": ")
        doc = hotel.knowledge_documents.create!(
          title: title,
          source_type: "text",
          category: "policy",
          language: "en",
          embedding_status: "pending",
          tags: [],
          effective_date: nil,
          content: content
        )
        doc.chunks.create!(content: content, chunk_index: 0)
        migrated += 1
      end

      puts "Migrated #{migrated} documents for hotel #{hotel.id}" if migrated > 0
    end
  end

  desc "Clear all AI Concierge data for a specific hotel (prospects and their conversation states/messages)"
  desc "Clear all AI Concierge data for a specific hotel (prospects and their conversation states/messages)"
  task :clear_ai_concierge, [ :hotel_name ] => :environment do |_, args|
    hotel = find_hotel(args[:hotel_name])
    next unless hotel

    puts "!!! WARNING: This will PERMANENTLY DELETE AI Concierge data for '#{hotel.name}' !!!"
    puts "  - All prospects and their conversation states/messages"
    puts "Starting in 5 seconds... (Press Ctrl+C to abort)"
    5.times do |i|
      print "#{5 - i}... "
      sleep 1
    end
    puts "\nProceeding..."

    delete_ai_concierge_data(hotel)

    puts "\nSUCCESS: AI Concierge data for '#{hotel.name}' has been cleared."
  end

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

    clean_hotel_state_records(hotel)

    puts "\nSUCCESS: '#{hotel.name}' has been recalibrated to a clean state."
  end

  desc "Clean state and trigger a realistic day-by-day operations simulation scenario"
  task :realtime_state, [ :hotel_name ] => :environment do |_, args|
    hotel_name = args[:hotel_name]
    if hotel_name.blank?
      puts "Error: Please provide a hotel name. Usage: bin/rake hotel_ops:realtime_state['Hotel Name']"
      exit 1
    end

    hotel = Hotel.where("name ILIKE ?", hotel_name).first

    if hotel.nil?
      puts "Error: Hotel '#{hotel_name}' not found."
      exit 1
    end

    puts "!!! WARNING: This will PERMANENTLY DELETE all bookings and night audits, then reset rates/statuses and simulate operations for '#{hotel.name}' !!!"
    puts "Starting in 5 seconds... (Press Ctrl+C to abort)"
    5.times do |i|
      print "#{5 - i}... "
      sleep 1
    end
    puts "\nProceeding..."

    clean_hotel_state_records(hotel)
    booking_scenario_state(hotel)

    puts "\nSUCCESS: '#{hotel.name}' has been recalibrated and simulation scenario loaded."
  end
end

def find_hotel(hotel_name)
  if hotel_name.blank?
    puts "Error: Please provide a hotel name. Usage: bin/rake hotel_ops:task['Hotel Name']"
    return nil
  end

  hotel = Hotel.where("name ILIKE ?", hotel_name).first
  if hotel.nil?
    puts "Error: Hotel '#{hotel_name}' not found."
    return nil
  end

  hotel
end

def delete_ai_concierge_data(hotel)
  ActiveRecord::Base.transaction do
    prospect_count = hotel.prospects.count
    puts "Deleting #{prospect_count} prospects with their conversation states and messages..."
    hotel.prospects.destroy_all
  end
end

def clean_hotel_state_records(hotel)
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

    # 1c. Recalibrate GL Mappings
    puts "Recalibrating General Ledger mappings..."
    Financials::EnsureDefaultGlMaps.call(hotel)

    # 1d. Clean Immutable Audit Logs
    puts "Force cleaning #{FinancialAuditEvent.where(hotel_id: hotel.id).count} immutable audit events..."
    FinancialAuditEvent.where(hotel_id: hotel.id).delete_all

    puts "Cleaning operational and audit logs..."
    BookingAuditLog.where(hotel_id: hotel.id).delete_all
    InventoryAuditLog.where(hotel_id: hotel.id).delete_all
    RoomOperationalAuditLog.where(hotel_id: hotel.id).delete_all
    NotificationDelivery.where(hotel_id: hotel.id).delete_all

    # 1e. Clean Journal Batches
    journal_batch_count = hotel.journal_batches.count
    puts "Destroying #{journal_batch_count} journal batches..."
    hotel.journal_batches.destroy_all

    # 2. Clean Night Audits
    night_audit_count = hotel.night_audits.count
    puts "Destroying #{night_audit_count} night audits..."
    hotel.night_audits.destroy_all

    # 2b. Clean Business Dates
    business_date_count = hotel.hotel_business_dates.count
    puts "Destroying #{business_date_count} business dates..."
    hotel.hotel_business_dates.destroy_all

    # 2. Clean Bookings
    booking_ids = hotel.bookings.pluck(:id)
    folio_ids = BookingFolio.where(booking_id: booking_ids).pluck(:id)

    puts "Force cleaning #{FolioTransaction.where(booking_folio_id: folio_ids).count} immutable transactions..."
    FolioTransaction.where(booking_folio_id: folio_ids).delete_all

    puts "Cleaning #{PaymentTransaction.where(booking_id: booking_ids).count} payment transactions..."
    PaymentTransaction.where(booking_id: booking_ids).destroy_all

    booking_count = hotel.bookings.count
    puts "Destroying #{booking_count} bookings..."
    hotel.bookings.destroy_all

    # 3. Clean and Recalibrate Rates
    start_date = Date.current - 10.days
    end_date = Date.new(Date.current.year, 12, 31)

    puts "Recalibrating rates and inventories from #{start_date} to #{end_date}..."
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
      puts "  -> Configuring rates and inventories for #{room_type.name} (Base: #{base_price})..."

      # 2b. Remove existing rates and inventories for this room type in the range
      RoomRate.where(room_type_id: room_type.id, date: start_date..end_date).delete_all
      RoomInventory.where(room_type_id: room_type.id, date: start_date..end_date).delete_all

      # 2c. Create new rates and inventories for all plans
      rates_to_insert = []
      inventories_to_insert = []
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

        # Inventory
        inventories_to_insert << {
          room_type_id: room_type.id,
          date: date,
          quantity: room_type.quantity,
          status: "open",
          available_room_numbers: room_type.room_numbers,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      RoomRate.insert_all(rates_to_insert) if rates_to_insert.any?
      RoomInventory.insert_all(inventories_to_insert) if inventories_to_insert.any?
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

    # 5. Clean AI Concierge data
    delete_ai_concierge_data(hotel)

    # 5b. Recalibrate Nearby Attractions
    puts "Recalibrating nearby attractions..."
    hotel.nearby_attractions.destroy_all
    hotel.nearby_attractions.create!([
      { name: "City Centre", description: "Explore the vibrant city centre with shops, restaurants, and cultural landmarks.", address: "City Centre", city: hotel.city, country: hotel.country },
      { name: "Local Market", description: "Experience local life and find unique souvenirs at the bustling market.", address: "Market Street", city: hotel.city, country: hotel.country },
      { name: "City Park", description: "Enjoy a relaxing day surrounded by nature.", address: "Park Avenue", city: hotel.city, country: hotel.country }
    ])

    # 7. Trigger Sync if needed
    if hotel.preferred_channel_manager.present?
      puts "Triggering Channel Manager Sync..."
      ChannelManagers::SyncJob.perform_later(hotel.id, start_date, end_date)
    end
  end
end

def booking_scenario_state(hotel)
  guest_profiles = [
    # Malaysia
    { country: "Malaysia", name: "Ahmad Bin Ibrahim", email: "ahmad.ibrahim@example.com", phone: "+60123456789", document_type: "ic", government_id: "920310-14-5183" },
    { country: "Malaysia", name: "Siti Aminah Binti Mansor", email: "siti.aminah@example.com", phone: "+60139876543", document_type: "ic", government_id: "950101-14-1234" },
    { country: "Malaysia", name: "Tan Wei Shen", email: "tan.weishen@example.com", phone: "+60172345678", document_type: "ic", government_id: "931205-10-5679" },
    { country: "Malaysia", name: "Muthu Kumar", email: "muthu.kumar@example.com", phone: "+60163456789", document_type: "ic", government_id: "900820-08-6011" },
    { country: "Malaysia", name: "Nurul Izzah", email: "nurul.izzah@example.com", phone: "+60194567890", document_type: "ic", government_id: "940515-14-5544" },
    # Japan
    { country: "Japan", name: "Kenji Sato", email: "kenji.sato@example.co.jp", phone: "+819012345678", document_type: "passport", government_id: "TK9876543" },
    { country: "Japan", name: "Yuka Tanaka", email: "yuka.tanaka@example.co.jp", phone: "+819087654321", document_type: "passport", government_id: "TK1234567" },
    { country: "Japan", name: "Hiroshi Watanabe", email: "hiroshi.watanabe@example.co.jp", phone: "+818023456789", document_type: "passport", government_id: "TK2345678" },
    { country: "Japan", name: "Mai Takahashi", email: "mai.takahashi@example.co.jp", phone: "+818034567890", document_type: "passport", government_id: "TK3456789" },
    { country: "Japan", name: "Takashi Kobayashi", email: "takashi.kobayashi@example.co.jp", phone: "+819045678901", document_type: "passport", government_id: "TK4567890" },
    # South Korea
    { country: "South Korea", name: "Min-jun Kim", email: "minjun.kim@example.co.kr", phone: "+821012345678", document_type: "passport", government_id: "M12345678" },
    { country: "South Korea", name: "Seo-yeon Lee", email: "seoyeon.lee@example.co.kr", phone: "+821087654321", document_type: "passport", government_id: "M23456789" },
    { country: "South Korea", name: "Ji-hoon Park", email: "jihoon.park@example.co.kr", phone: "+821023456789", document_type: "passport", government_id: "M34567890" },
    { country: "South Korea", name: "Ji-woo Choi", email: "jiwoo.choi@example.co.kr", phone: "+821034567890", document_type: "passport", government_id: "M45678901" },
    { country: "South Korea", name: "Hyun-woo Jung", email: "hyunwoo.jung@example.co.kr", phone: "+821045678901", document_type: "passport", government_id: "M56789012" },
    # Hong Kong
    { country: "Hong Kong", name: "Chun-hei Chan", email: "chunhei.chan@example.com.hk", phone: "+85291234567", document_type: "passport", government_id: "H98765432" },
    { country: "Hong Kong", name: "Hoi-ching Wong", email: "hoiching.wong@example.com.hk", phone: "+85298765432", document_type: "passport", government_id: "H12345678" },
    { country: "Hong Kong", name: "Yat-long Lee", email: "yatlong.lee@example.com.hk", phone: "+85292345678", document_type: "passport", government_id: "H23456789" },
    { country: "Hong Kong", name: "Wing-shan Cheung", email: "wingshan.cheung@example.com.hk", phone: "+85293456789", document_type: "passport", government_id: "H34567890" },
    { country: "Hong Kong", name: "Tsz-hin Ng", email: "tszhin.ng@example.com.hk", phone: "+85294567890", document_type: "passport", government_id: "H45678901" },
    # Indonesia
    { country: "Indonesia", name: "Budi Santoso", email: "budi.santoso@example.co.id", phone: "+628123456789", document_type: "passport", government_id: "B9876543" },
    { country: "Indonesia", name: "Dewi Lestari", email: "dewi.lestari@example.co.id", phone: "+6281398765432", document_type: "passport", government_id: "B1234567" },
    { country: "Indonesia", name: "Aditya Wijaya", email: "aditya.wijaya@example.co.id", phone: "+6281723456789", document_type: "passport", government_id: "B2345678" },
    { country: "Indonesia", name: "Putri Indah", email: "putri.indah@example.co.id", phone: "+6281634567890", document_type: "passport", government_id: "B3456789" },
    { country: "Indonesia", name: "Joko Widodo", email: "joko.widodo@example.co.id", phone: "+6281945678901", document_type: "passport", government_id: "B4567890" }
  ]

  puts "Prefilling realistic Malaysia and Foreigner guest bookings via day-by-day operations simulation..."

  # Resolve the acting user (hotel owner/admin) to satisfy service layer audit requirements.
  # A superadmin user bypasses override_financial_date_lock permission checks for closed date postings.
  acting_user = hotel.account.users.first
  # When no user is present (e.g. test factory hotels), use system_posting mode to bypass user requirement.
  system_posting = acting_user.nil?
  puts "  -> Acting user for simulation: #{acting_user&.name || 'system (no user found)'}"

  # 1. First, assign room numbers and build all bookings in "confirmed" status
  assigned_rooms = Hash.new { |h, k| h[k] = [] }

  guest_profiles.each_with_index do |profile, index|
    # 1a. Guest creation / retrieval
    guest = Guest.find_or_initialize_by(email: profile[:email])
    guest.assign_attributes(
      name: profile[:name],
      phone: profile[:phone],
      country: profile[:country],
      document_type: profile[:document_type],
      government_id: profile[:government_id],
      created_by_hotel: hotel
    )
    guest.save!

    # 1b. Stay dates calculation
    check_in = Date.current + ((index % 9) - 5).days
    nights = (index % 4) + 1
    check_out = check_in + nights.days

    # 1c. Room type assignment
    room_type = hotel.room_types[index % hotel.room_types.count]
    standard_plan = room_type.rate_plans.find_by(name: "Standard Rate") || room_type.rate_plans.first

    # 1d. Room assignment with overlap check
    occupied_rooms = assigned_rooms[room_type.id].select do |assigned|
      assigned[:check_in] < check_out && check_in < assigned[:check_out]
    end.map { |assigned| assigned[:room_number] }

    available_room_numbers = room_type.room_numbers.map(&:to_s)
    room_number = (available_room_numbers - occupied_rooms).first
    room_number ||= available_room_numbers.first # fallback

    assigned_rooms[room_type.id] << { check_in: check_in, check_out: check_out, room_number: room_number }

    # 1e. Financial calculations
    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel,
      check_in: check_in,
      check_out: check_out,
      guest_country: profile[:country],
      room_type: room_type,
      rate_plan: standard_plan,
      quantity: 1
    ).call

    tourism_tax_item = snapshot.tax_lines.find { |tax| tax["type"].to_s == "tourism_tax" }
    tourism_tax_amount = tourism_tax_item ? tourism_tax_item["amount"].to_d : 0.to_d

    total_amount = snapshot.room_total + snapshot.tax_total

    # Create the confirmed booking — mirrors CreateManualBooking with record_payment: true
    # payment_status: 'captured' + PaymentTransaction at booking time so that when
    # check-in runs Folios::InitializeForBooking -> SyncExistingPayments, the folio
    # immediately shows the correct credit balance.
    booking = hotel.bookings.new(
      check_in: check_in,
      check_out: check_out,
      guest_name: guest.name,
      guest_email: guest.email,
      guest_phone: guest.phone,
      guest_country: guest.country,
      adults: 2,
      children: 0,
      currency: hotel.default_currency || "MYR",
      total_amount: total_amount,
      tax_lines: snapshot.tax_lines,
      tax_posting_snapshot: snapshot.tax_posting_snapshot,
      tourism_tax_amount: tourism_tax_amount,
      tourism_tax_applied: tourism_tax_amount.positive?,
      payment_status: "captured",
      status: "confirmed"
    )

    # Build the payment transaction in-memory so it's saved atomically with the booking.
    # captured_at is set to tomorrow so SyncExistingPayments always posts the booking_payment
    # FolioTransaction to a business date that has NOT yet been audited, avoiding PostingGuard
    # conflicts regardless of which day in the 5-day simulation the check-in falls on.
    booking.payment_transactions.build(
      gateway: "manual",
      payment_method: "cash",
      amount_subunits: (total_amount * 100).to_i,
      currency: hotel.default_currency || "MYR",
      status: "captured",
      captured_at: (Date.current + 1.day).beginning_of_day,
      event_source: "manual_booking",
      metadata: { simulation: true }
    )

    booking.save!

    booking.booking_guests.create!(guest: guest, is_primary: true)

    booking.booking_rooms.create!(
      room_type: room_type,
      rate_plan: standard_plan,
      quantity: 1,
      subtotal: snapshot.room_total,
      nightly_rate_snapshot: snapshot.nightly_rate_snapshot,
      room_number: room_number
    )
  end

  # 2. Sequential day-by-day operations simulation
  simulation_start_date = Date.current - 5.days
  HotelBusinessDate.create!(
    hotel: hotel,
    business_date: simulation_start_date,
    status: "open",
    opened_at: Time.current,
    blockers_snapshot: {}
  )

  zone = Time.find_zone(hotel.time_zone.presence || "Kuala Lumpur")

  (simulation_start_date..Date.current).each do |date|
    puts "Simulating hotel operations for business date: #{date}..."

    # 2a. Check-ins: Bookings::TransitionStatus internally calls
    #   booking.transition_status_to! + Folios::InitializeForBooking
    #   (mirrors standard_booking_lifecycle_spec check-in flow)
    hotel.bookings.where(check_in: date).each do |booking|
      profile_index = guest_profiles.index { |p| p[:email] == booking.guest_email }
      is_no_show = [ 12, 20 ].include?(profile_index)
      next if is_no_show

      check_in_time = zone.local(date.year, date.month, date.day, 14, 0, 0)
      result = Bookings::TransitionStatus.new(
        booking: booking,
        status: "checked_in",
        timestamp: check_in_time,
        user: acting_user,
        # override_night_audit: true lets SyncExistingPayments post the booking_payment
        # FolioTransaction even if the business date has already been rolled over by night audit.
        # system_posting is a fallback for test environments where acting_user may be nil.
        options: { override_night_audit: true, reason: "Simulation seeding", system_posting: system_posting }
      ).call
      raise "Failed to check in booking #{booking.id}: #{result.error}" unless result.success?
    end


    # 2b. Check-outs and late checkout transitions
    hotel.bookings.where(check_out: date).each do |booking|
      profile_index = guest_profiles.index { |p| p[:email] == booking.guest_email }
      is_late_checkout = [ 2, 4 ].include?(profile_index)

      if is_late_checkout && date == Date.current
        # --- Late Checkout ---
        # Step 1: Transition to review_due_out via Bookings::TransitionStatus
        late_checkout_time = zone.local(date.year, date.month, date.day, 13, 0, 0)
        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "review_due_out",
          timestamp: late_checkout_time,
          user: acting_user
        ).call
        raise "Failed to transition booking #{booking.id} to review_due_out: #{result.error}" unless result.success?

        # Step 2: Post late checkout charge via Folios::PostCategoryCharge
        #   (mirrors exception_booking_lifecycle_spec #7: Folios::PostCategoryCharge.call)
        charge_result = Folios::PostCategoryCharge.call(
          folio: booking.booking_folio,
          user: acting_user,
          category: "late_checkout_charge",
          amount: 50.0,
          description: "Late Checkout Charge",
          options: { system_posting: system_posting }
        )
        raise "Failed to post late checkout charge for booking #{booking.id}: #{charge_result.error}" unless charge_result.success?

      elsif booking.status == "checked_in"
        # --- Regular Checkout ---
        # The booking was pre-paid at creation time (PaymentTransaction gateway: 'manual').
        # SyncExistingPayments already synced that payment into the folio on check-in,
        # so no additional payment posting is needed here — just close the folio.
        check_out_time = zone.local(date.year, date.month, date.day, 11, 0, 0)
        folio = booking.booking_folio

        # Step 2: Close folio and complete booking via Bookings::TransitionStatus
        #   (internally calls Folios::CloseForCheckout + booking.transition_status_to!)
        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "completed",
          timestamp: check_out_time,
          user: acting_user
        ).call
        raise "Failed to check out booking #{booking.id}: #{result.error}" unless result.success?

        booking.update!(payment_status: "captured")
      end
    end

    # 2c. Run Night Audit for the business date (if it's in the past)
    #   Passes acting_user so audit logs have a proper actor recorded
    if date < Date.current
      result = HotelOps::RunNightAudit.new(
        hotel: hotel,
        business_date: date,
        performed_by_user: acting_user,
        trigger_mode: "manual",
        allow_unclosable_date: true
      ).call
      raise "Failed to complete night audit for date #{date}: #{result.error}" unless result.success?
    end
  end
end
