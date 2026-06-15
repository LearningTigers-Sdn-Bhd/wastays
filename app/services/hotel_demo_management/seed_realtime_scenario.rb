# frozen_string_literal: true

module HotelDemoManagement
  class SeedRealtimeScenario
    Result = Struct.new(:success?, :hotel, :error, keyword_init: true)

    def initialize(hotel:, logger: ResetState::NoopLogger.new, embed: false)
      @hotel = hotel
      @logger = logger
      @embed = embed
    end

    def call
      reset_result = ResetState.new(hotel: @hotel, logger: @logger, embed: @embed).call
      return failure(reset_result.error) unless reset_result.success?

      setup_error = validate_room_setup
      return failure(setup_error) if setup_error

      seed_booking_scenario
      success
    rescue StandardError => e
      failure(e.message)
    end

    private

    def success
      Result.new(success?: true, hotel: @hotel)
    end

    def failure(error)
      Result.new(success?: false, hotel: @hotel, error: error)
    end

    def validate_room_setup
      return "Hotel must have at least one room type before realtime demo state can be seeded." if @hotel.room_types.empty?

      missing_plan = @hotel.room_types.detect { |room_type| room_type.rate_plans.exists? == false }
      return "Room type '#{missing_plan.name}' must have at least one rate plan." if missing_plan

      nil
    end

    def seed_booking_scenario
      @logger.puts "Prefilling realistic Malaysia and Foreigner guest bookings via day-by-day operations simulation..."

      acting_user = @hotel.account.users.first
      system_posting = acting_user.nil?
      @logger.puts "  -> Acting user for simulation: #{acting_user&.name || 'system (no user found)'}"

      assigned_rooms = Hash.new { |hash, key| hash[key] = [] }
      guest_profiles.each_with_index do |profile, index|
        create_simulation_booking(profile, index, assigned_rooms)
      end

      run_day_by_day_simulation(acting_user: acting_user, system_posting: system_posting)
    end

    def create_simulation_booking(profile, index, assigned_rooms)
      guest = Guest.find_or_initialize_by(email: profile[:email])
      guest.assign_attributes(
        name: profile[:name],
        phone: profile[:phone],
        country: profile[:country],
        document_type: profile[:document_type],
        government_id: profile[:government_id],
        created_by_hotel: @hotel
      )
      guest.save!

      check_in = Date.current + ((index % 9) - 5).days
      nights = (index % 4) + 1
      check_out = check_in + nights.days

      room_type = @hotel.room_types[index % @hotel.room_types.count]
      standard_plan = room_type.rate_plans.find_by(name: "Standard Rate") || room_type.rate_plans.first

      occupied_rooms = assigned_rooms[room_type.id].select do |assigned|
        assigned[:check_in] < check_out && check_in < assigned[:check_out]
      end.map { |assigned| assigned[:room_number] }

      available_room_numbers = room_type.room_numbers.map(&:to_s)
      room_number = (available_room_numbers - occupied_rooms).first
      room_number ||= available_room_numbers.first

      assigned_rooms[room_type.id] << { check_in: check_in, check_out: check_out, room_number: room_number }

      snapshot = Bookings::BuildFinancialSnapshot.new(
        hotel: @hotel,
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

      booking = @hotel.bookings.new(
        check_in: check_in,
        check_out: check_out,
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        guest_country: guest.country,
        adults: 2,
        children: 0,
        currency: @hotel.default_currency || "MYR",
        total_amount: total_amount,
        tax_lines: snapshot.tax_lines,
        tax_posting_snapshot: snapshot.tax_posting_snapshot,
        tourism_tax_amount: tourism_tax_amount,
        tourism_tax_applied: tourism_tax_amount.positive?,
        payment_status: "captured",
        status: "confirmed"
      )

      booking.payment_transactions.build(
        gateway: "manual",
        payment_method: "cash",
        amount_subunits: (total_amount * 100).to_i,
        currency: @hotel.default_currency || "MYR",
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

    def run_day_by_day_simulation(acting_user:, system_posting:)
      simulation_start_date = Date.current - 5.days
      BusinessDates::ResetAuthority.call!(hotel: @hotel, date: simulation_start_date)

      zone = Time.find_zone(@hotel.time_zone.presence || "Kuala Lumpur")

      (simulation_start_date..Date.current).each do |date|
        @logger.puts "Simulating hotel operations for business date: #{date}..."
        check_in_bookings(date, zone, acting_user, system_posting)
        check_out_bookings(date, zone, acting_user, system_posting)
        run_night_audit(date, acting_user) if date < Date.current
      end
    end

    def check_in_bookings(date, zone, acting_user, system_posting)
      @hotel.bookings.checking_in_on(date, @hotel.hotel_time_zone).each do |booking|
        profile_index = guest_profiles.index { |profile| profile[:email] == booking.guest_email }
        is_no_show = [ 12, 20 ].include?(profile_index)
        next if is_no_show

        check_in_time = zone.local(date.year, date.month, date.day, 14, 0, 0)
        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "checked_in",
          timestamp: check_in_time,
          user: acting_user,
          options: { override_night_audit: true, reason: "Simulation seeding", system_posting: system_posting }
        ).call
        raise "Failed to check in booking #{booking.id}: #{result.error}" unless result.success?
      end
    end

    def check_out_bookings(date, zone, acting_user, system_posting)
      @hotel.bookings.checking_out_on(date, @hotel.hotel_time_zone).each do |booking|
        profile_index = guest_profiles.index { |profile| profile[:email] == booking.guest_email }
        is_late_checkout = [ 2, 4 ].include?(profile_index)

        if is_late_checkout && date == Date.current
          transition_to_late_checkout(booking, date, zone, acting_user, system_posting)
        elsif booking.status == "checked_in"
          complete_checkout(booking, date, zone, acting_user)
        end
      end
    end

    def transition_to_late_checkout(booking, date, zone, acting_user, system_posting)
      late_checkout_time = zone.local(date.year, date.month, date.day, 13, 0, 0)
      result = Bookings::TransitionStatus.new(
        booking: booking,
        status: "review_due_out",
        timestamp: late_checkout_time,
        user: acting_user
      ).call
      raise "Failed to transition booking #{booking.id} to review_due_out: #{result.error}" unless result.success?

      charge_result = Folios::PostCategoryCharge.call(
        folio: booking.booking_folio,
        user: acting_user,
        category: "late_checkout_charge",
        amount: 50.0,
        description: "Late Checkout Charge",
        options: { system_posting: system_posting }
      )
      raise "Failed to post late checkout charge for booking #{booking.id}: #{charge_result.error}" unless charge_result.success?
    end

    def complete_checkout(booking, date, zone, acting_user)
      check_out_time = zone.local(date.year, date.month, date.day, 11, 0, 0)
      result = Bookings::TransitionStatus.new(
        booking: booking,
        status: "completed",
        timestamp: check_out_time,
        user: acting_user
      ).call
      raise "Failed to check out booking #{booking.id}: #{result.error}" unless result.success?

      booking.update!(payment_status: "captured")
    end

    def run_night_audit(date, acting_user)
      result = NightAudits::Run.new(
        hotel: @hotel,
        business_date: date,
        performed_by_user: acting_user,
        trigger_mode: "manual",
        allow_unclosable_date: true
      ).call
      raise "Failed to complete night audit for date #{date}: #{result.error}" unless result.success?
    end

    def guest_profiles
      @guest_profiles ||= [
        { country: "Malaysia", name: "Ahmad Bin Ibrahim", email: "ahmad.ibrahim@example.com", phone: "+60123456789", document_type: "ic", government_id: "920310-14-5183" },
        { country: "Malaysia", name: "Siti Aminah Binti Mansor", email: "siti.aminah@example.com", phone: "+60139876543", document_type: "ic", government_id: "950101-14-1234" },
        { country: "Malaysia", name: "Tan Wei Shen", email: "tan.weishen@example.com", phone: "+60172345678", document_type: "ic", government_id: "931205-10-5679" },
        { country: "Malaysia", name: "Muthu Kumar", email: "muthu.kumar@example.com", phone: "+60163456789", document_type: "ic", government_id: "900820-08-6011" },
        { country: "Malaysia", name: "Nurul Izzah", email: "nurul.izzah@example.com", phone: "+60194567890", document_type: "ic", government_id: "940515-14-5544" },
        { country: "Japan", name: "Kenji Sato", email: "kenji.sato@example.co.jp", phone: "+819012345678", document_type: "passport", government_id: "TK9876543" },
        { country: "Japan", name: "Yuka Tanaka", email: "yuka.tanaka@example.co.jp", phone: "+819087654321", document_type: "passport", government_id: "TK1234567" },
        { country: "Japan", name: "Hiroshi Watanabe", email: "hiroshi.watanabe@example.co.jp", phone: "+818023456789", document_type: "passport", government_id: "TK2345678" },
        { country: "Japan", name: "Mai Takahashi", email: "mai.takahashi@example.co.jp", phone: "+818034567890", document_type: "passport", government_id: "TK3456789" },
        { country: "Japan", name: "Takashi Kobayashi", email: "takashi.kobayashi@example.co.jp", phone: "+819045678901", document_type: "passport", government_id: "TK4567890" },
        { country: "South Korea", name: "Min-jun Kim", email: "minjun.kim@example.co.kr", phone: "+821012345678", document_type: "passport", government_id: "M12345678" },
        { country: "South Korea", name: "Seo-yeon Lee", email: "seoyeon.lee@example.co.kr", phone: "+821087654321", document_type: "passport", government_id: "M23456789" },
        { country: "South Korea", name: "Ji-hoon Park", email: "jihoon.park@example.co.kr", phone: "+821023456789", document_type: "passport", government_id: "M34567890" },
        { country: "South Korea", name: "Ji-woo Choi", email: "jiwoo.choi@example.co.kr", phone: "+821034567890", document_type: "passport", government_id: "M45678901" },
        { country: "South Korea", name: "Hyun-woo Jung", email: "hyunwoo.jung@example.co.kr", phone: "+821045678901", document_type: "passport", government_id: "M56789012" },
        { country: "Hong Kong", name: "Chun-hei Chan", email: "chunhei.chan@example.com.hk", phone: "+85291234567", document_type: "passport", government_id: "H98765432" },
        { country: "Hong Kong", name: "Hoi-ching Wong", email: "hoiching.wong@example.com.hk", phone: "+85298765432", document_type: "passport", government_id: "H12345678" },
        { country: "Hong Kong", name: "Yat-long Lee", email: "yatlong.lee@example.com.hk", phone: "+85292345678", document_type: "passport", government_id: "H23456789" },
        { country: "Hong Kong", name: "Wing-shan Cheung", email: "wingshan.cheung@example.com.hk", phone: "+85293456789", document_type: "passport", government_id: "H34567890" },
        { country: "Hong Kong", name: "Tsz-hin Ng", email: "tszhin.ng@example.com.hk", phone: "+85294567890", document_type: "passport", government_id: "H45678901" },
        { country: "Indonesia", name: "Budi Santoso", email: "budi.santoso@example.co.id", phone: "+628123456789", document_type: "passport", government_id: "B9876543" },
        { country: "Indonesia", name: "Dewi Lestari", email: "dewi.lestari@example.co.id", phone: "+6281398765432", document_type: "passport", government_id: "B1234567" },
        { country: "Indonesia", name: "Aditya Wijaya", email: "aditya.wijaya@example.co.id", phone: "+6281723456789", document_type: "passport", government_id: "B2345678" },
        { country: "Indonesia", name: "Putri Indah", email: "putri.indah@example.co.id", phone: "+6281634567890", document_type: "passport", government_id: "B3456789" },
        { country: "Indonesia", name: "Joko Widodo", email: "joko.widodo@example.co.id", phone: "+6281945678901", document_type: "passport", government_id: "B4567890" }
      ]
    end
  end
end
