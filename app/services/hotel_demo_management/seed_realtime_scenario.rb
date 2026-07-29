# frozen_string_literal: true

module HotelDemoManagement
  class SeedRealtimeScenario
    Result = Struct.new(:success?, :hotel, :error, keyword_init: true)

    DEFAULT_BOOKING_COUNT = 1_000
    DEFAULT_GROUP_COUNT = 100
    DEFAULT_HISTORY_DAYS = 365
    DEFAULT_FUTURE_DAYS = 30
    BOOKING_SOURCES = %w[booking agoda expedia traveloka airbnb walk_in internal].freeze
    COMPANY_BLUEPRINTS = [
      { key: "meridian", name: "Meridian Business Solutions Sdn Bhd", payment_terms_days: 30 },
      { key: "northstar", name: "Northstar Holdings Sdn Bhd", payment_terms_days: 30 },
      { key: "strata", name: "Strata Professional Services Sdn Bhd", payment_terms_days: 14 }
    ].freeze

    def initialize(hotel:, logger: ResetState::NoopLogger.new, embed: false, booking_count: DEFAULT_BOOKING_COUNT,
      group_count: DEFAULT_GROUP_COUNT, history_days: DEFAULT_HISTORY_DAYS, future_days: DEFAULT_FUTURE_DAYS)
      @hotel = hotel
      @logger = logger
      @embed = embed
      @booking_count = booking_count
      @group_count = group_count
      @history_days = history_days
      @future_days = future_days
    end

    def call
      with_booking_creation_notifications_suppressed do
        ActiveRecord::Base.transaction do
          reset_result = ResetState.new(hotel: @hotel, logger: @logger, embed: @embed).call
          raise reset_result.error unless reset_result.success?

          setup_error = validate_room_setup
          raise setup_error if setup_error

          seed_booking_scenario
        end
      end
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

    def with_booking_creation_notifications_suppressed
      previous_value = Thread.current[:skip_booking_creation_notifications]
      Thread.current[:skip_booking_creation_notifications] = true
      yield
    ensure
      Thread.current[:skip_booking_creation_notifications] = previous_value
    end

    def validate_room_setup
      sellable_room_types = @hotel.room_types.select { |room_type| room_type.quantity.positive? && room_type.room_numbers.any? }
      return "Hotel must have at least one sellable room before realtime demo state can be seeded." if sellable_room_types.empty?

      missing_plan = sellable_room_types.detect { |room_type| room_type.rate_plans.exists? == false }
      return "Room type '#{missing_plan.name}' must have at least one rate plan." if missing_plan

      nil
    end

    def seed_booking_scenario
      @logger.puts "Prefilling #{@booking_count} bookings across one year of day-by-day hotel operations..."

      acting_user = @hotel.account.users.first
      system_posting = acting_user.nil?
      @logger.puts "  -> Acting user for simulation: #{acting_user&.name || 'system (no user found)'}"
      ensure_company_relationships

      assigned_rooms = Hash.new { |hash, key| hash[key] = [] }
      created_bookings = booking_scenarios.each_with_index.filter_map do |scenario, index|
        booking = create_simulation_booking(profile_for(index), index, scenario, assigned_rooms)
        [ scenario, booking ] if booking
      end
      @seeded_booking_ids = created_bookings.map { |_scenario, booking| booking.id }
      seed_group_bookings(created_bookings, acting_user)
      seed_company_billing(created_bookings, acting_user)

      run_day_by_day_simulation(acting_user: acting_user, system_posting: system_posting)
      sync_group_statuses
      settle_company_invoices(acting_user)
    end

    def create_simulation_booking(profile, index, scenario, assigned_rooms)
      check_in = scenario[:check_in]
      nights = scenario[:nights]
      check_out = check_in + nights.days
      assignment = available_room_assignment(index, check_in, check_out, assigned_rooms)

      unless assignment
        @logger.puts "  -> Skipping #{profile[:name]} because no room is available for #{check_in} to #{check_out}."
        return
      end

      room_type, room_number = assignment
      guest = Guest.find_or_initialize_by(email: profile[:email])
      guest.assign_attributes(
        name: profile[:name],
        phone: profile[:phone],
        gender: profile[:gender],
        country: profile[:country],
        document_type: profile[:document_type],
        government_id: profile[:government_id],
        date_of_birth: profile[:date_of_birth],
        created_by_hotel: @hotel
      )
      guest.save!

      standard_plan = room_type.rate_plans.find_by(name: "Standard Rate") || room_type.rate_plans.first

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
      reservation_created_at = completed_operation_time(check_in - (7 + (index % 45)).days, hour: 9)
      payment_captured_at = completed_operation_time(check_in - 1.day, hour: 12)
      company_booking = scenario[:company_key].present?

      booking = @hotel.bookings.new(
        check_in: check_in,
        check_out: check_out,
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        guest_gender: guest.gender,
        guest_country: guest.country,
        guest_document_type: guest.document_type,
        adults: 2,
        children: 0,
        currency: @hotel.default_currency || "MYR",
        total_amount: total_amount,
        tax_lines: snapshot.tax_lines,
        tax_posting_snapshot: snapshot.tax_posting_snapshot,
        tourism_tax_amount: tourism_tax_amount,
        tourism_tax_applied: tourism_tax_amount.positive?,
        payment_status: company_booking ? "pending" : "captured",
        pre_checkin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "not_required",
        source: company_booking ? "corporate" : BOOKING_SOURCES[index % BOOKING_SOURCES.size],
        hotel_snapshot: @hotel.booking_snapshot.merge("room_number" => room_number),
        created_at: reservation_created_at,
        status: "confirmed"
      )

      unless company_booking
        booking.payment_transactions.build(
          gateway: "manual",
          payment_method: "cash",
          amount_subunits: (total_amount * 100).to_i,
          currency: @hotel.default_currency || "MYR",
          status: "captured",
          captured_at: payment_captured_at,
          created_at: payment_captured_at,
          event_source: "manual_booking",
          metadata: { simulation: true }
        )
      end

      booking.save!
      booking.booking_guests.create!(guest: guest, is_primary: true)
      booking.create_pre_checkin!(
        status: "completed",
        document_status: "verified",
        signature_status: "signed",
        completed_at: completed_operation_time(check_in - 1.day, hour: 10),
        created_at: reservation_created_at
      )
      booking.booking_rooms.create!(
        room_type: room_type,
        rate_plan: standard_plan,
        subtotal: snapshot.room_total,
        nightly_rate_snapshot: snapshot.nightly_rate_snapshot,
        room_number: room_number
      )

      booking
    end

    def booking_scenarios
      @booking_scenarios ||= begin
        scenarios = group_scenarios
        single_count = @booking_count - scenarios.size
        window = @history_days + @future_days + 1
        start_date = current_hotel_date - @history_days.days

        single_count.times do |index|
          scenarios << {
            check_in: start_date + ((index * 53 + 19) % window).days,
            nights: stay_length(index),
            group_key: nil,
            company_key: (COMPANY_BLUEPRINTS[(index / 5) % COMPANY_BLUEPRINTS.size][:key] if (index % 5).zero?)
          }
        end

        scenarios.sort_by { |scenario| [ scenario[:check_in], scenario[:group_key].to_s ] }
      end
    end

    def group_scenarios
      scenarios = []
      window = @history_days + @future_days + 1
      start_date = current_hotel_date - @history_days.days

      [ @group_count, @booking_count / 2 ].min.times do |index|
        size = 2 + (index % 3)
        break if scenarios.size + size > @booking_count

        check_in = start_date + ((index * 37 + 7) % window).days
        size.times do
          scenarios << {
            check_in: check_in,
            nights: 1 + (index % 3),
            group_key: index,
            company_key: (COMPANY_BLUEPRINTS[(index / 3) % COMPANY_BLUEPRINTS.size][:key] if (index % 3).zero?)
          }
        end
      end

      scenarios
    end

    def stay_length(index)
      return 1 if (index % 10) < 7
      return 2 if (index % 10) < 9

      3
    end

    def profile_for(index)
      profile = guest_profiles[index % guest_profiles.size].dup
      local, domain = profile[:email].split("@", 2)
      profile[:email] = "#{local}+#{@hotel.slug}@#{domain}"
      profile
    end

    def seed_group_bookings(created_bookings, acting_user)
      created_bookings.group_by { |scenario, _booking| scenario[:group_key] }.each do |group_key, entries|
        next if group_key.nil? || entries.size < 2

        bookings = entries.map(&:last)
        result = GroupBookings::CreateFromBookings.call(
          hotel: @hotel,
          bookings: bookings,
          attributes: {
            name: "Demo Group #{group_key + 1}",
            status: "active",
            source: "internal",
            organizer_guest: bookings.first.primary_guest,
            default_check_in: bookings.first.check_in.to_date,
            default_check_out: bookings.first.check_out.to_date,
            created_at: bookings.map(&:created_at).min
          },
          actor: acting_user
        )
        raise "Failed to create demo group #{group_key + 1}: #{result.error}" unless result.success?
      end
    end

    def ensure_company_relationships
      @company_relationships = COMPANY_BLUEPRINTS.to_h do |blueprint|
        account = Account.find_or_initialize_by(slug: "demo-hotel-#{@hotel.id}-#{blueprint[:key]}")
        account.assign_attributes(name: blueprint[:name], status: "active", account_kind: "corporate")
        account.save!

        relationship = @hotel.hotel_corporate_accounts.find_or_initialize_by(corporate_account: account)
        relationship.assign_attributes(
          account_type: "company",
          relationship_type: "direct_bill",
          status: "active",
          credit_limit: 1_000_000,
          credit_currency: @hotel.default_currency || "MYR",
          payment_terms_days: blueprint[:payment_terms_days],
          contact_email: "accounts@#{blueprint[:key]}.example"
        )
        relationship.save!
        [ blueprint[:key], relationship ]
      end
    end

    def seed_company_billing(created_bookings, acting_user)
      created_bookings.each do |scenario, booking|
        next if scenario[:company_key].nil?

        Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: acting_user)
        relationship = @company_relationships.fetch(scenario[:company_key])
        party_result = BookingBillingParties::ManageCompany.call(
          booking: booking,
          actor: acting_user,
          attributes: {
            hotel_corporate_account_id: relationship.id,
            account_type: "company",
            settlement_type: "city_ledger",
            purchase_order_reference: "DEMO-PO-#{booking.id}"
          }
        )
        raise "Failed to configure company terms for booking #{booking.id}: #{party_result.error}" unless party_result.success?

        result = Folios::Routing::BillRoomChargesToCompany.call(
          booking: booking,
          actor: acting_user,
          hotel_corporate_account_id: relationship.id,
          settlement_type: "city_ledger",
          bill_tourism_tax_to_company: true
        )
        raise "Failed to configure company billing for booking #{booking.id}: #{result.error}" unless result.success?
      end
    end

    def available_room_assignment(index, check_in, check_out, assigned_rooms)
      candidates = weighted_room_types.rotate(index % weighted_room_types.size).uniq
      candidates.each do |room_type|
        occupied_rooms = assigned_rooms[room_type.id].select do |assigned|
          assigned[:check_in] < check_out && check_in < assigned[:check_out]
        end.map { |assigned| assigned[:room_number] }

        configured_rooms = room_type.room_numbers.first(room_type.quantity).map(&:to_s)
        room_number = (configured_rooms - occupied_rooms).first
        return [ room_type, room_number ] if room_number
      end

      nil
    end

    def weighted_room_types
      @weighted_room_types ||= @hotel.room_types.flat_map do |room_type|
        [ room_type ] * room_type.quantity
      end.shuffle(random: Random.new(42))
    end

    def current_hotel_date
      @current_hotel_date ||= Time.current.in_time_zone(@hotel.hotel_time_zone).to_date
    end

    def completed_operation_time(date, hour:)
      [ date.in_time_zone(@hotel.hotel_time_zone).change(hour: hour), Time.current ].min
    end

    def run_day_by_day_simulation(acting_user:, system_posting:)
      simulation_start_date = current_hotel_date - @history_days.days
      BusinessDates::ResetAuthority.call!(hotel: @hotel, date: simulation_start_date)

      (simulation_start_date..current_hotel_date).each do |date|
        @logger.puts "Simulating hotel operations for business date: #{date}..." if date.day == 1 || date == current_hotel_date
        check_in_bookings(date, acting_user, system_posting)
        check_out_bookings(date, acting_user)
        run_night_audit(date, acting_user) if date < current_hotel_date
      end
    end

    def check_in_bookings(date, acting_user, system_posting)
      @hotel.bookings.checking_in_on(date, @hotel.hotel_time_zone).each do |booking|
        check_in_time = completed_operation_time(date, hour: 14)
        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "checked_in",
          timestamp: check_in_time,
          user: acting_user,
          options: {
            override_night_audit: true,
            reason: "Simulation seeding",
            system_posting: system_posting,
            defer_side_effects: true
          }
        ).call
        raise "Failed to check in booking #{booking.id}: #{result.error}" unless result.success?
      end
    end

    def check_out_bookings(date, acting_user)
      @hotel.bookings.checking_out_on(date, @hotel.hotel_time_zone).each do |booking|
        complete_checkout(booking, date, acting_user) if booking.status == "checked_in"
      end
    end

    def complete_checkout(booking, date, acting_user)
      check_out_time = completed_operation_time(date, hour: 11)
      company_folio_ids = booking.booking_folios.where(payer_type: "company").ids
      options = { defer_side_effects: true }
      options[:direct_bill_folio_ids] = company_folio_ids if company_folio_ids.any?
      result = Bookings::TransitionStatus.new(
        booking: booking,
        status: "completed",
        timestamp: check_out_time,
        user: acting_user,
        options: options
      ).call
      raise "Failed to check out booking #{booking.id}: #{result.error}" unless result.success?

      booking.update!(payment_status: "captured") if company_folio_ids.empty?
      complete_historical_checkout_cleaning(booking) if date < current_hotel_date
    end

    def complete_historical_checkout_cleaning(booking)
      requests = booking.check_out_requests.where(status: %w[new assigned in_progress pending acknowledged]).order(:id)

      ActiveRecord::Base.transaction do
        requests.each do |request|
          %w[in_progress completed].each do |status|
            result = HotelPortal::Requests::StatusUpdater.new(
              hotel: @hotel,
              kind: :checkout,
              request_id: request.id,
              status: status,
              trigger_webhook: false
            ).call
            raise "Failed to mark checkout cleaning #{status} for booking #{booking.id}" unless result
          end
        end
      end
    end

    def sync_group_statuses
      @hotel.group_bookings.find_each do |group_booking|
        group_booking.update!(status: group_booking.projected_status)
      end
    end

    def settle_company_invoices(acting_user)
      @company_relationships.each_value do |relationship|
        relationship.ar_invoices.with_open_balance
          .joins(booking_folio: :booking)
          .where(bookings: { id: @seeded_booking_ids })
          .includes(:booking_folio)
          .group_by { |invoice| [ invoice.issued_on.beginning_of_month, invoice.currency ] }
          .each do |(month, currency), invoices|
          amount = invoices.sum { |invoice| invoice.outstanding_amount.to_d }
          result = ArPayments::RecordPayment.call(
            hotel: @hotel,
            hotel_corporate_account: relationship,
            user: acting_user,
            amount: amount,
            currency: currency,
            reference_number: "DEMO-#{relationship.id}-#{month.strftime('%Y%m')}-#{currency}",
            received_at: [ invoices.map(&:due_on).max, current_hotel_date ].min,
            payment_method: "bank_transfer",
            notes: "Demo company account settlement",
            allocations: invoices.to_h { |invoice| [ invoice.id, invoice.outstanding_amount ] },
            metadata: { simulation: true }
          )
          raise "Failed to settle company invoices for #{relationship.corporate_account.name}: #{result.error}" unless result.success?
        end
      end
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
        { country: "Malaysia", name: "Ahmad Bin Ibrahim", email: "ahmad.ibrahim@example.com", phone: "+60123456789", gender: "male", document_type: "ic", government_id: "920310-14-5183", date_of_birth: Date.new(1992, 3, 10) },
        { country: "Malaysia", name: "Siti Aminah Binti Mansor", email: "siti.aminah@example.com", phone: "+60139876543", gender: "female", document_type: "ic", government_id: "950101-14-1234", date_of_birth: Date.new(1995, 1, 1) },
        { country: "Malaysia", name: "Tan Wei Shen", email: "tan.weishen@example.com", phone: "+60172345678", gender: "male", document_type: "ic", government_id: "931205-10-5679", date_of_birth: Date.new(1993, 12, 5) },
        { country: "Malaysia", name: "Muthu Kumar", email: "muthu.kumar@example.com", phone: "+60163456789", gender: "male", document_type: "ic", government_id: "900820-08-6011", date_of_birth: Date.new(1990, 8, 20) },
        { country: "Malaysia", name: "Nurul Izzah", email: "nurul.izzah@example.com", phone: "+60194567890", gender: "female", document_type: "ic", government_id: "940515-14-5544", date_of_birth: Date.new(1994, 5, 15) },
        { country: "Japan", name: "Kenji Sato", email: "kenji.sato@example.co.jp", phone: "+819012345678", gender: "male", document_type: "passport", government_id: "TK9876543", date_of_birth: Date.new(1988, 5, 14) },
        { country: "Japan", name: "Yuka Tanaka", email: "yuka.tanaka@example.co.jp", phone: "+819087654321", gender: "female", document_type: "passport", government_id: "TK1234567", date_of_birth: Date.new(1992, 1, 22) },
        { country: "Japan", name: "Hiroshi Watanabe", email: "hiroshi.watanabe@example.co.jp", phone: "+818023456789", gender: "male", document_type: "passport", government_id: "TK2345678", date_of_birth: Date.new(1985, 9, 3) },
        { country: "Japan", name: "Mai Takahashi", email: "mai.takahashi@example.co.jp", phone: "+818034567890", gender: "female", document_type: "passport", government_id: "TK3456789", date_of_birth: Date.new(1994, 7, 11) },
        { country: "Japan", name: "Takashi Kobayashi", email: "takashi.kobayashi@example.co.jp", phone: "+819045678901", gender: "male", document_type: "passport", government_id: "TK4567890", date_of_birth: Date.new(1989, 12, 28) },
        { country: "South Korea", name: "Min-jun Kim", email: "minjun.kim@example.co.kr", phone: "+821012345678", gender: "male", document_type: "passport", government_id: "M12345678", date_of_birth: Date.new(1991, 4, 6) },
        { country: "South Korea", name: "Seo-yeon Lee", email: "seoyeon.lee@example.co.kr", phone: "+821087654321", gender: "female", document_type: "passport", government_id: "M23456789", date_of_birth: Date.new(1993, 8, 19) },
        { country: "South Korea", name: "Ji-hoon Park", email: "jihoon.park@example.co.kr", phone: "+821023456789", gender: "male", document_type: "passport", government_id: "M34567890", date_of_birth: Date.new(1987, 3, 25) },
        { country: "South Korea", name: "Ji-woo Choi", email: "jiwoo.choi@example.co.kr", phone: "+821034567890", gender: "female", document_type: "passport", government_id: "M45678901", date_of_birth: Date.new(1996, 10, 2) },
        { country: "South Korea", name: "Hyun-woo Jung", email: "hyunwoo.jung@example.co.kr", phone: "+821045678901", gender: "male", document_type: "passport", government_id: "M56789012", date_of_birth: Date.new(1990, 6, 15) },
        { country: "Hong Kong", name: "Chun-hei Chan", email: "chunhei.chan@example.com.hk", phone: "+85291234567", gender: "male", document_type: "passport", government_id: "H98765432", date_of_birth: Date.new(1986, 11, 8) },
        { country: "Hong Kong", name: "Hoi-ching Wong", email: "hoiching.wong@example.com.hk", phone: "+85298765432", gender: "female", document_type: "passport", government_id: "H12345678", date_of_birth: Date.new(1995, 2, 17) },
        { country: "Hong Kong", name: "Yat-long Lee", email: "yatlong.lee@example.com.hk", phone: "+85292345678", gender: "male", document_type: "passport", government_id: "H23456789", date_of_birth: Date.new(1984, 1, 30) },
        { country: "Hong Kong", name: "Wing-shan Cheung", email: "wingshan.cheung@example.com.hk", phone: "+85293456789", gender: "female", document_type: "passport", government_id: "H34567890", date_of_birth: Date.new(1997, 9, 9) },
        { country: "Hong Kong", name: "Tsz-hin Ng", email: "tszhin.ng@example.com.hk", phone: "+85294567890", gender: "male", document_type: "passport", government_id: "H45678901", date_of_birth: Date.new(1991, 12, 4) },
        { country: "Indonesia", name: "Budi Santoso", email: "budi.santoso@example.co.id", phone: "+628123456789", gender: "male", document_type: "passport", government_id: "B9876543", date_of_birth: Date.new(1988, 4, 12) },
        { country: "Indonesia", name: "Dewi Lestari", email: "dewi.lestari@example.co.id", phone: "+6281398765432", gender: "female", document_type: "passport", government_id: "B1234567", date_of_birth: Date.new(1993, 7, 21) },
        { country: "Indonesia", name: "Aditya Wijaya", email: "aditya.wijaya@example.co.id", phone: "+6281723456789", gender: "male", document_type: "passport", government_id: "B2345678", date_of_birth: Date.new(1987, 5, 5) },
        { country: "Indonesia", name: "Putri Indah", email: "putri.indah@example.co.id", phone: "+6281634567890", gender: "female", document_type: "passport", government_id: "B3456789", date_of_birth: Date.new(1998, 3, 14) },
        { country: "Indonesia", name: "Joko Widodo", email: "joko.widodo@example.co.id", phone: "+6281945678901", gender: "male", document_type: "passport", government_id: "B4567890", date_of_birth: Date.new(1985, 8, 27) }
      ]
    end
  end
end
