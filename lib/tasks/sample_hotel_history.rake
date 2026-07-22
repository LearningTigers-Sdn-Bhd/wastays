# frozen_string_literal: true

module SampleHotelHistory
  SEED = 20260101
  HOTEL_OPENED_ON = Date.new(2026, 1, 1)

  SOURCE_WEIGHTS = {
    "booking_com" => 28,
    "agoda" => 16,
    "walk_in" => 12,
    "expedia" => 9,
    "phone" => 7,
    "traveloka" => 7,
    "airbnb" => 6,
    "whatsapp" => 6,
    "email" => 5,
    "internal" => 4
  }.freeze

  COUNTRY_WEIGHTS = {
    "Malaysia" => 42,
    "Singapore" => 12,
    "Indonesia" => 9,
    "China" => 7,
    "India" => 6,
    "Australia" => 5,
    "United Kingdom" => 5,
    "Philippines" => 5,
    "South Korea" => 4,
    "Japan" => 3,
    "Germany" => 2
  }.freeze

  PHONE_COUNTRY_CODES = {
    "Malaysia" => "60",
    "Singapore" => "65",
    "Indonesia" => "62",
    "China" => "86",
    "India" => "91",
    "Australia" => "61",
    "United Kingdom" => "44",
    "Philippines" => "63",
    "South Korea" => "82",
    "Japan" => "81",
    "Germany" => "49"
  }.freeze

  NAME_POOLS = {
    "Malaysia" => {
      first_male: %w[Ahmad Muhammad Amirul Hafiz Farid Zulkifli Azman Faisal Rizal Iskandar Hakim Syafiq Wei-Jian Kok-Wei Jun-Hao Chee-Keong Boon-Hui Ravi Suresh Kumar Arun Vijay Prakash],
      first_female: %w[Nurul Siti Aisyah Farah Aina Sofea Balqis Nadia Zulaikha Fatin Alia Diana Mei-Ling Xin-Yi Hui-Min Li-Wen Shu-Fen Priya Kavitha Deepa Anita Meena Shalini],
      last: %w[Abdullah Rahman Ismail Hassan Yusof Ibrahim Karim Salleh Mahmud Osman Hamid Tan Lim Lee Wong Chong Ng Ong Teh Yap Chua Menon Nair Pillai Subramaniam]
    },
    "Singapore" => {
      first_male: %w[Wei Jun Kai Zhi-Hao Jing-Wei Darren Kevin Ravi Arjun Iskandar],
      first_female: %w[Hui-Ying Jia-Yi Mei Xin Charlotte Priya Kavya Nur],
      last: %w[Tan Lim Lee Ong Koh Goh Chua Nair Rahman]
    },
    "Indonesia" => {
      first_male: %w[Budi Agus Eko Dedi Rian Andi Bayu Hendra],
      first_female: %w[Siti Dewi Rina Wulan Putri Ayu Rani Indah],
      last: %w[Santoso Wijaya Kusuma Setiawan Pratama Hidayat Wibowo Saputra]
    },
    "China" => {
      first_male: %w[Wei Jun Feng Hao Qiang Lei Ming Bo],
      first_female: %w[Fang Yan Xin Hui Ling Jing Mei Ying],
      last: %w[Zhang Wang Li Chen Liu Yang Huang Zhao]
    },
    "India" => {
      first_male: %w[Rajesh Amit Vikram Sanjay Arjun Rohit Karan Nikhil],
      first_female: %w[Pooja Neha Kavya Divya Shreya Anjali Ritu Sneha],
      last: %w[Sharma Gupta Patel Reddy Iyer Nair Rao Menon]
    },
    "Australia" => {
      first_male: %w[James Michael David Daniel Andrew Mark Ryan Liam],
      first_female: %w[Emma Sarah Jessica Laura Olivia Charlotte Chloe Grace],
      last: %w[Smith Johnson Williams Brown Taylor Anderson Wilson Clarke]
    },
    "United Kingdom" => {
      first_male: %w[Oliver Jack Harry George Thomas William Charlie Henry],
      first_female: %w[Amelia Isla Ava Freya Poppy Ruby Ella Sophie],
      last: %w[Smith Jones Taylor Evans Roberts Walker Wright Hughes]
    },
    "Philippines" => {
      first_male: %w[Jose Juan Mark Paulo Ramon Miguel Angelo Ferdinand],
      first_female: %w[Maria Ana Grace Rosario Carmen Liza Joy Erika],
      last: %w[Santos Reyes Cruz Bautista Garcia Torres Ramos Mercado]
    },
    "South Korea" => {
      first_male: %w[Min-jun Joon-ho Do-yoon Ji-hoon Seo-jun Tae-yang],
      first_female: %w[Ji-woo Seo-yeon Ha-eun Yuna Soo-min Eun-ji],
      last: %w[Kim Lee Park Choi Jung Kang]
    },
    "Japan" => {
      first_male: %w[Hiroshi Kenji Takashi Yuto Sora Daiki],
      first_female: %w[Yuki Sakura Aiko Haruka Mei Rin],
      last: %w[Sato Suzuki Takahashi Tanaka Watanabe Ito]
    },
    "Germany" => {
      first_male: %w[Lukas Max Felix Jonas Paul Niklas],
      first_female: %w[Anna Lea Mia Laura Sophie Emilia],
      last: %w[Mueller Schmidt Schneider Fischer Weber Wagner]
    }
  }.freeze

  EMAIL_DOMAINS = %w[gmail.com yahoo.com outlook.com icloud.com hotmail.com].freeze

  BLACKLIST_REASONS = [
    "Caused significant property damage to the room (broken furniture, stained carpet) during a previous stay; charges were disputed and never settled.",
    "Repeated noise complaints from neighboring guests and refused to comply with quiet-hours requests after multiple warnings.",
    "Departed without settling an outstanding folio balance.",
    "Verbally abusive towards front desk staff during check-out.",
    "Smoked inside a non-smoking room on multiple occasions, triggering the fire alarm and an evacuation.",
    "Attempted to pay with a card later flagged as stolen by the payment gateway's fraud check.",
    "Brought unauthorized additional guests beyond the room's occupancy limit and refused to pay the surcharge.",
    "No-showed on two confirmed reservations without cancelling, causing avoidable revenue loss.",
    "Provided a falsified identification document during guest registration."
  ].freeze

  ROOM_NIGHT_WEIGHTS = [ 1, 1, 2, 2, 2, 3, 3, 4, 5 ].freeze

  module_function

  def weighted_sample(rng, weights)
    total = weights.values.sum
    point = rng.rand(total)
    weights.each do |key, weight|
      return key if point < weight

      point -= weight
    end
    weights.keys.last
  end

  def build_guest_attrs(rng, index, country_weights: COUNTRY_WEIGHTS)
    country = weighted_sample(rng, country_weights)
    pool = NAME_POOLS.fetch(country)
    gender = rng.rand < 0.5 ? "male" : "female"
    first_name = gender == "male" ? pool[:first_male].sample(random: rng) : pool[:first_female].sample(random: rng)
    last_name = pool[:last].sample(random: rng)
    name = "#{first_name} #{last_name}"
    domain = EMAIL_DOMAINS.sample(random: rng)
    email = "#{first_name.downcase.gsub(/[^a-z]/, '')}.#{last_name.downcase.gsub(/[^a-z]/, '')}#{index}@#{domain}"
    document_type = country == "Malaysia" ? "ic" : "passport"
    government_id = if document_type == "ic"
      "#{rng.rand(65..99)}#{format('%02d', rng.rand(1..12))}#{format('%02d', rng.rand(1..28))}-#{format('%02d', rng.rand(10..16))}-#{format('%04d', rng.rand(1000..9999))}"
    else
      "#{('A'..'Z').to_a.sample(random: rng)}#{rng.rand(1_000_000..9_999_999)}"
    end
    date_of_birth = Date.current - rng.rand(21..70).years - rng.rand(0..364).days

    {
      name: name,
      email: email,
      phone: "+#{PHONE_COUNTRY_CODES.fetch(country)}#{rng.rand(100_000_000..999_999_999)}",
      gender: gender,
      country: country,
      document_type: document_type,
      government_id: government_id,
      date_of_birth: date_of_birth
    }
  end

  def build_stay_dates(rng, check_in_range:, max_check_in:)
    nights = ROOM_NIGHT_WEIGHTS.sample(random: rng)
    latest_check_in = [ max_check_in, check_in_range.end ].min
    span = (latest_check_in - check_in_range.begin).to_i
    span = 0 if span.negative?
    check_in = check_in_range.begin + rng.rand(0..span).days
    [ check_in, nights ]
  end

  def guarantee_and_deposit_for(rng, status)
    case status
    when "completed", "checked_in"
      [ "pre_checkin_completed", "collected" ]
    when "cancelled"
      [ "none", "not_required" ]
    when "no_show"
      [ "manual_at_hotel", "failed" ]
    when "confirmed"
      rng.rand < 0.6 ? [ "manual_at_hotel", "pending_at_hotel" ] : [ "card_authorization_document", "authorized" ]
    else # pending
      [ "none", "not_required" ]
    end
  end

  def payment_status_for(status)
    case status
    when "completed", "checked_in" then "captured"
    when "cancelled" then "refunded"
    when "no_show" then "failed"
    when "pending" then "pending"
    else "authorized"
    end
  end

  def upsert_guest(guest_attrs)
    ActiveRecord::Encryption.without_encryption do
      guest = Guest.find_or_initialize_by(email: guest_attrs[:email])
      guest.name = guest_attrs[:name]
      guest.phone = guest_attrs[:phone]
      guest.gender = guest_attrs[:gender]
      guest.country = guest_attrs[:country]
      guest.document_type = guest_attrs[:document_type]
      guest.government_id = guest_attrs[:government_id]
      guest.date_of_birth = guest_attrs[:date_of_birth]
      guest.save!
      guest
    end
  end

  def create_booking(hotel:, room_types:, guest_attrs:, check_in:, nights:, status:, source:, rng:, room_type: nil, room_number: nil)
    return nil if Booking.exists?(hotel: hotel, guest_email: guest_attrs[:email], check_in: check_in)

    room_type ||= room_types.sample(random: rng)
    adults = [ 1, 1, 2, 2, 2, 3 ].sample(random: rng).clamp(1, room_type.max_adults)
    children = rng.rand < 0.2 ? rng.rand(1..[ room_type.max_children, 1 ].max).clamp(0, room_type.max_children) : 0
    nights = nights.clamp(1, 14)
    check_out = check_in + nights.days
    tourism_tax_applied = guest_attrs[:country] != "Malaysia"

    guarantee, deposit = guarantee_and_deposit_for(rng, status)
    booked_at = [ check_in.to_time - rng.rand(1..30).days, HOTEL_OPENED_ON.to_time ].max

    booking = Booking.create!(
      hotel: hotel,
      guest_name: guest_attrs[:name],
      guest_email: guest_attrs[:email],
      guest_phone: guest_attrs[:phone],
      guest_gender: guest_attrs[:gender],
      guest_country: guest_attrs[:country],
      guest_document_type: guest_attrs[:document_type],
      check_in: check_in,
      check_out: check_out,
      adults: adults,
      children: children,
      currency: "MYR",
      total_amount: room_type.base_price * nights,
      status: status,
      payment_status: payment_status_for(status),
      source: source,
      guarantee_method: guarantee,
      deposit_status: deposit,
      tourism_tax_applied: tourism_tax_applied,
      tourism_tax_amount: tourism_tax_applied ? hotel.send(:tourism_tax_amount_for, guest_attrs[:country]) : 0,
      created_at: booked_at
    )

    BookingRoom.create!(booking: booking, room_type: room_type, room_number: room_number, subtotal: room_type.base_price * nights)

    guest = upsert_guest(guest_attrs)
    BookingGuest.find_or_create_by!(booking: booking, guest: guest, is_primary: true)

    PreCheckin.find_or_create_by!(booking: booking) do |pre_checkin|
      completed = %w[completed checked_in].include?(status)
      pre_checkin.status = completed ? "completed" : "pending"
      pre_checkin.document_status = completed ? "verified" : "pending"
      pre_checkin.signature_status = completed ? "signed" : "pending"
    end

    if status == "checked_in"
      booking.update_columns(checked_in_at: check_in.to_time + 15.hours)
    elsif status == "completed"
      booking.update_columns(checked_in_at: check_in.to_time + 15.hours, checked_out_at: check_out.to_time + 11.hours)
    end

    margin_rate = hotel.effective_margin_rate.to_f
    margin_amount = (booking.total_amount * (margin_rate / 100.0)).round(2)
    booking.update_columns(margin_rate: margin_rate, margin_amount: margin_amount, net_amount: booking.total_amount - margin_amount)

    guest
  end
end

namespace :sample_hotel do
  desc "Backfills Sample Hotel with realistic guest & booking history since Jan 1 (past stays, current in-house, and future bookings)"
  task seed_history: :environment do
    hotel = Hotel.find_by(account: Account.find_by(slug: "sample-account"), name: "Sample Hotel")
    raise "Sample Hotel not found — run `bin/rails db:seed` first." unless hotel

    room_types = hotel.room_types.order(:name).to_a
    raise "Sample Hotel has no room types configured." if room_types.empty?

    rng = Random.new(SampleHotelHistory::SEED)
    today = Date.current

    puts "\n== Seeding Sample Hotel booking history #{'=' * 40}"
    puts "-> Hotel opened: #{SampleHotelHistory::HOTEL_OPENED_ON}, today: #{today}"

    past_guests = 500.times.map { |i| SampleHotelHistory.build_guest_attrs(rng, i) }

    vip_indices = (0...past_guests.size).to_a.sample(25, random: rng).to_set
    remaining_indices = (0...past_guests.size).to_a - vip_indices.to_a
    blacklist_indices = remaining_indices.sample(10, random: rng)
    blacklist_reasons = {}
    blacklist_indices.each { |i| blacklist_reasons[i] = SampleHotelHistory::BLACKLIST_REASONS.sample(random: rng) }

    created_guests = 0
    created_bookings = 0

    past_guests.each_with_index do |guest_attrs, i|
      status = case rng.rand
      when 0...0.92 then "completed"
      when 0.92...0.97 then "cancelled"
      else "no_show"
      end

      check_in, nights = SampleHotelHistory.build_stay_dates(
        rng,
        check_in_range: (SampleHotelHistory::HOTEL_OPENED_ON..(today - 3.days)),
        max_check_in: today - 3.days
      )
      source = SampleHotelHistory.weighted_sample(rng, SampleHotelHistory::SOURCE_WEIGHTS)

      guest = SampleHotelHistory.create_booking(
        hotel: hotel, room_types: room_types, guest_attrs: guest_attrs,
        check_in: check_in, nights: nights, status: status, source: source, rng: rng
      )
      next unless guest

      created_bookings += 1
      created_guests += 1 if guest.previously_new_record?

      if vip_indices.include?(i)
        guest.update!(vip: true)
      end

      if blacklist_reasons.key?(i)
        guest.update!(blacklisted: true)
        guest.metadata ||= {}
        guest.metadata["blacklisted_hotel_ids"] = [ hotel.id ]
        guest.metadata["blacklist_reason"] = blacklist_reasons[i]
        guest.metadata["blacklisted_at"] = Time.current.iso8601
        guest.save!
      end

      # Repeat stays: ~15% of guests return for a second visit, a few for a third.
      next unless rng.rand < 0.15

      2.times do |visit|
        break if visit == 1 && rng.rand > 0.2

        repeat_check_in, repeat_nights = SampleHotelHistory.build_stay_dates(
          rng,
          check_in_range: (SampleHotelHistory::HOTEL_OPENED_ON..(today - 3.days)),
          max_check_in: today - 3.days
        )
        repeat_source = SampleHotelHistory.weighted_sample(rng, SampleHotelHistory::SOURCE_WEIGHTS)
        repeat_status = rng.rand < 0.95 ? "completed" : "cancelled"

        if SampleHotelHistory.create_booking(
          hotel: hotel, room_types: room_types, guest_attrs: guest_attrs,
          check_in: repeat_check_in, nights: repeat_nights, status: repeat_status, source: repeat_source, rng: rng
        )
          created_bookings += 1
        end
      end
    end

    puts "-> Past guests processed: #{past_guests.size} (#{created_guests} new, #{created_bookings} bookings so far)"

    # Current: guests staying right now (some in-house, some arriving/departing today).
    current_specs = []
    5.times { current_specs << { check_in: today - rng.rand(1..3).days, check_out: today + rng.rand(1..3).days, status: "checked_in" } }
    3.times { current_specs << { check_in: today, check_out: today + rng.rand(1..3).days, status: "confirmed" } }
    2.times { current_specs << { check_in: today - rng.rand(1..3).days, check_out: today, status: "checked_in" } }

    current_specs.each do |spec|
      reuse_existing = rng.rand < 0.4
      guest_attrs = reuse_existing ? past_guests.sample(random: rng) : SampleHotelHistory.build_guest_attrs(rng, 1000 + created_bookings)
      nights = (spec[:check_out] - spec[:check_in]).to_i.clamp(1, 14)
      source = SampleHotelHistory.weighted_sample(rng, SampleHotelHistory::SOURCE_WEIGHTS)

      if SampleHotelHistory.create_booking(
        hotel: hotel, room_types: room_types, guest_attrs: guest_attrs,
        check_in: spec[:check_in], nights: nights, status: spec[:status], source: source, rng: rng
      )
        created_bookings += 1
      end
    end

    puts "-> Current in-house / arriving-today bookings seeded (#{current_specs.size})"

    # Future: upcoming confirmed (and a few pending) bookings over the next 40 days.
    future_count = 30
    future_count.times do |i|
      reuse_existing = rng.rand < 0.3
      guest_attrs = reuse_existing ? past_guests.sample(random: rng) : SampleHotelHistory.build_guest_attrs(rng, 2000 + i)
      check_in = today + rng.rand(1..40).days
      nights = SampleHotelHistory::ROOM_NIGHT_WEIGHTS.sample(random: rng)
      status = rng.rand < 0.85 ? "confirmed" : "pending"
      source = SampleHotelHistory.weighted_sample(rng, SampleHotelHistory::SOURCE_WEIGHTS)

      if SampleHotelHistory.create_booking(
        hotel: hotel, room_types: room_types, guest_attrs: guest_attrs,
        check_in: check_in, nights: nights, status: status, source: source, rng: rng
      )
        created_bookings += 1
      end
    end

    puts "-> Future bookings seeded (#{future_count})"
    puts "== Done: #{created_bookings} bookings created for Sample Hotel (#{Guest.joins(:bookings).where(bookings: { hotel_id: hotel.id }).distinct.count} distinct guests on file) #{'=' * 10}"
  end

  desc "Adds more checked-in arrivals for today and confirmed arrivals for tomorrow, with a VIP/blacklisted mix and varied booking sources"
  task seed_more_arrivals: :environment do
    hotel = Hotel.find_by(account: Account.find_by(slug: "sample-account"), name: "Sample Hotel")
    raise "Sample Hotel not found — run `bin/rails db:seed` first." unless hotel

    room_types = hotel.room_types.order(:name).to_a
    raise "Sample Hotel has no room types configured." if room_types.empty?

    rng = Random.new(SampleHotelHistory::SEED + 1)
    today = Date.current
    tomorrow = today + 1.day

    occupied_room_numbers = ->(date) do
      hotel.bookings.active
           .joins(:booking_rooms)
           .where(":date >= check_in::date AND :date < check_out::date", date: date)
           .pluck("booking_rooms.room_number").compact.to_set
    end

    assign_room_number = ->(room_type, date, taken) do
      available = room_type.room_numbers - taken.to_a
      return nil if available.empty?

      number = available.sample(random: rng)
      taken << number
      number
    end

    puts "\n== Adding more Sample Hotel arrivals #{'=' * 30}"

    # Today: 10 more checked-in guests. VIP first, then blacklisted, then the rest.
    today_taken = occupied_room_numbers.call(today)
    today_created = 0

    10.times do |i|
      guest_attrs = SampleHotelHistory.build_guest_attrs(rng, 5000 + i)
      room_type = room_types.sample(random: rng)
      nights = [ 1, 2, 2, 3, 3, 4 ].sample(random: rng)
      source = SampleHotelHistory.weighted_sample(rng, SampleHotelHistory::SOURCE_WEIGHTS)
      room_number = assign_room_number.call(room_type, today, today_taken)

      guest = SampleHotelHistory.create_booking(
        hotel: hotel, room_types: room_types, guest_attrs: guest_attrs,
        check_in: today, nights: nights, status: "checked_in", source: source, rng: rng,
        room_type: room_type, room_number: room_number
      )
      next unless guest

      today_created += 1

      case i
      when 0, 1, 2
        guest.update!(vip: true)
      when 3, 4
        guest.update!(blacklisted: true)
        guest.metadata ||= {}
        guest.metadata["blacklisted_hotel_ids"] = [ hotel.id ]
        guest.metadata["blacklist_reason"] = SampleHotelHistory::BLACKLIST_REASONS.sample(random: rng)
        guest.metadata["blacklisted_at"] = Time.current.iso8601
        guest.save!
      end
    end

    puts "-> Today: #{today_created} checked-in arrivals added (3 VIP, 2 blacklisted, #{today_created - 5} regular)"

    # Tomorrow: 15 confirmed guests, mixed booking sources (OTA, direct, manual channels).
    tomorrow_source_weights = SampleHotelHistory::SOURCE_WEIGHTS.merge("direct" => 20)
    tomorrow_taken = occupied_room_numbers.call(tomorrow)
    tomorrow_created = 0

    15.times do |i|
      guest_attrs = SampleHotelHistory.build_guest_attrs(rng, 6000 + i)
      room_type = room_types.sample(random: rng)
      nights = SampleHotelHistory::ROOM_NIGHT_WEIGHTS.sample(random: rng)
      source = SampleHotelHistory.weighted_sample(rng, tomorrow_source_weights)
      room_number = rng.rand < 0.4 ? assign_room_number.call(room_type, tomorrow, tomorrow_taken) : nil

      guest = SampleHotelHistory.create_booking(
        hotel: hotel, room_types: room_types, guest_attrs: guest_attrs,
        check_in: tomorrow, nights: nights, status: "confirmed", source: source, rng: rng,
        room_type: room_type, room_number: room_number
      )
      next unless guest

      tomorrow_created += 1

      case i
      when 0
        guest.update!(vip: true)
      when 1
        guest.update!(blacklisted: true)
        guest.metadata ||= {}
        guest.metadata["blacklisted_hotel_ids"] = [ hotel.id ]
        guest.metadata["blacklist_reason"] = SampleHotelHistory::BLACKLIST_REASONS.sample(random: rng)
        guest.metadata["blacklisted_at"] = Time.current.iso8601
        guest.save!
      end
    end

    puts "-> Tomorrow: #{tomorrow_created} confirmed arrivals added (1 VIP, 1 blacklisted, mixed sources)"
    puts "== Done #{'=' * 10}"
  end
end
