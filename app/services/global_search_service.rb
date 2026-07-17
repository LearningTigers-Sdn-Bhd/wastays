class GlobalSearchService
  include Rails.application.routes.url_helpers

  GROUP_PRIORITY = { "Bookings" => 0, "Pages" => 1, "Requests" => 2 }.freeze
  PAGE_RESULTS = [
    { title: "Hotel Dashboard", subtitle: "Overview and recent activity", route: :hotel_dashboard_path, keywords: "dashboard overview recent bookings" },
    { title: "Arrival Board", subtitle: "Check-ins and arrivals", route: :hotel_front_desk_path, tab: "arrivals", keywords: "arrival board arrivals check in" },
    { title: "In-House Guests", subtitle: "Current in-house guests", route: :hotel_front_desk_path, tab: "in_house", keywords: "in house guests" },
    { title: "Bookings", subtitle: "All hotel bookings", route: :hotel_front_desk_path, tab: "bookings", keywords: "bookings reservations recent bookings" },
    { title: "Requests", subtitle: "Housekeeping and complaints", route: :hotel_requests_path, keywords: "requests housekeeping complaints" },
    { title: "Guest Records", subtitle: "Past and upcoming guest history", route: :hotel_guests_path, keywords: "guest records guests" },
    { title: "Room Categories", subtitle: "Manage room types", route: :hotel_room_types_path, keywords: "room categories room types" },
    { title: "Rates & Inventory", subtitle: "Rates calendar and inventory", route: :hotel_inventory_index_path, keywords: "rates inventory calendar" },
    { title: "Reports", subtitle: "Financial performance", route: :hotel_reports_path, keywords: "reports financial performance" },
    { title: "Weekly Settlements", subtitle: "Payout reports", route: :payouts_hotel_reports_path, keywords: "payouts settlements weekly" },
    { title: "Operation Audit Logs", subtitle: "Operational changes history", route: :hotel_audit_logs_path, keywords: "audit logs operations" },
    { title: "Settings", subtitle: "Hotel and payment settings", route: :hotel_general_settings_path, keywords: "settings preferences payment" }
  ].freeze

  def initialize(hotel, query)
    @hotel = hotel
    @query = query.to_s.strip.downcase
  end

  def perform
    rows = page_results + booking_results + request_results
    rows = rows.uniq { |entry| [ entry[:title], entry[:url] ] }
    rows.sort_by { |entry| [ GROUP_PRIORITY.fetch(entry[:group], 99), -entry[:score].to_i ] }
        .first(20)
        .map { |entry| entry.except(:score) }
  end

  def quick_actions
    [
      { group: "Bookings", label: "Go to bookings", url: hotel_front_desk_path(@hotel, tab: "bookings") },
      { group: "Requests", label: "Go to requests", url: hotel_requests_path(@hotel) },
      { group: "Pages", label: "Go to arrival board", url: hotel_front_desk_path(@hotel, tab: "arrivals") }
    ]
  end

  private

  def page_results
    PAGE_RESULTS.filter_map do |entry|
      text = [ entry[:title], entry[:subtitle], entry[:keywords] ].join(" ").downcase
      score = search_score(text, @query)
      next if @query.present? && score.zero?

      {
        title: entry[:title],
        subtitle: entry[:subtitle],
        group: "Pages",
        url: hotel_portal_route(entry[:route], tab: entry[:tab]),
        score: score + 10
      }
    end
  end

  def booking_results
    return [] if @query.blank?

    bookings = @hotel.bookings.search(@query).order(created_at: :desc).limit(12)

    bookings.map do |booking|
      haystack = [
        booking.confirmation_token,
        booking.guest_name,
        booking.guest_email,
        booking.guest_phone
      ].join(" ").downcase

      {
        title: "#{booking.confirmation_token} · #{booking.guest_name}",
        subtitle: "#{booking.guest_email} · #{booking.guest_phone}",
        group: "Bookings",
        url: hotel_booking_control_panel_path(@hotel, booking, tab: "booking_details"),
        score: search_score(haystack, @query) + 6
      }
    end
  end

  def request_results
    return [] if @query.blank?

    housekeeping_rows = HousekeepingRequest.joins(:booking)
                                           .where(bookings: { hotel_id: @hotel.id })
                                           .search(@query)
                                           .order(requested_at: :desc)
                                           .limit(6)

    complaint_rows = ComplaintRequest.joins(:booking)
                                     .where(bookings: { hotel_id: @hotel.id })
                                     .search(@query)
                                     .order(requested_at: :desc)
                                     .limit(6)

    to_request_entries(housekeeping_rows, "Housekeeping") +
      to_request_entries(complaint_rows, "Complaint")
  end

  def to_request_entries(rows, label)
    rows.map do |request|
      booking = request.booking
      detail_text = request.respond_to?(:request_details) ? request.request_details : request.complaint_details
      haystack = [
        request.external_id,
        detail_text,
        booking&.confirmation_token,
        booking&.guest_name,
        booking&.guest_email,
        booking&.guest_phone
      ].join(" ").downcase

      {
        title: "#{label}: #{request.external_id || booking&.confirmation_token}",
        subtitle: "#{booking&.guest_name} · #{request.status.to_s.humanize}",
        group: "Requests",
        url: hotel_booking_control_panel_path(@hotel, booking, tab: "booking_details"),
        score: search_score(haystack, @query) + 5
      }
    end
  end

  def hotel_portal_route(route_name, tab: nil)
    send(route_name, @hotel, **{ tab: }.compact)
  end

  # --- Scoring Logic ---

  def search_score(text, query)
    return 1 if query.blank?

    score = 0
    score += 120 if text.include?(query)

    query_tokens = tokenize(query)
    text_tokens = tokenize(text)
    return 0 if query_tokens.empty? || text_tokens.empty?

    query_tokens.each do |query_token|
      best_token_score = text_tokens.map { |text_token| token_similarity_score(query_token, text_token) }.max.to_i
      score += best_token_score
    end

    score
  end

  def tokenize(text)
    text.to_s.downcase.scan(/[a-z0-9]+/)
  end

  def token_similarity_score(query_token, text_token)
    return 35 if text_token == query_token
    return 30 if text_token.start_with?(query_token)
    return 26 if text_token.include?(query_token)
    return 18 if subsequence_match?(query_token, text_token)

    distance = levenshtein_distance(query_token, text_token)
    return 14 if distance == 1
    return 9 if distance == 2

    0
  end

  def subsequence_match?(needle, haystack)
    index = 0
    needle.each_char do |char|
      found_index = haystack.index(char, index)
      return false if found_index.nil?

      index = found_index + 1
    end
    true
  end

  def levenshtein_distance(a, b)
    a_len = a.length
    b_len = b.length
    return b_len if a_len.zero?
    return a_len if b_len.zero?

    prev = (0..b_len).to_a
    curr = Array.new(b_len + 1, 0)

    (1..a_len).each do |i|
      curr[0] = i
      (1..b_len).each do |j|
        cost = a[i - 1] == b[j - 1] ? 0 : 1
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost
        ].min
      end
      prev, curr = curr, prev
    end

    prev[b_len]
  end
end
