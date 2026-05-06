# frozen_string_literal: true

class HotelPortal::GlobalSearchService < BaseGlobalSearchService
  GROUP_PRIORITY = { "Bookings" => 0, "Pages" => 1, "Requests" => 2 }.freeze
  PAGE_RESULTS = [
    { title: "Hotel Dashboard", subtitle: "Overview and recent activity", route: :hotel_dashboard_path, keywords: "dashboard overview recent bookings" },
    { title: "Arrival Board", subtitle: "Check-ins and arrivals", route: :hotel_arrivals_path, keywords: "arrival board arrivals check in" },
    { title: "Room Status", subtitle: "Live room status and occupancy timeline", route: :hotel_room_status_board_path, keywords: "tape chart room status housekeeping assignment" },
    { title: "In-House Guests", subtitle: "Current in-house guests", route: :hotel_in_house_guests_path, keywords: "in house guests" },
    { title: "Today's Check-Outs", subtitle: "Guests checked out today", route: :hotel_checked_out_guests_path, keywords: "today check outs checked out departures" },
    { title: "Bookings", subtitle: "All hotel bookings", route: :hotel_bookings_path, keywords: "bookings reservations recent bookings" },
    { title: "Requests", subtitle: "Housekeeping and complaints", route: :hotel_requests_path, keywords: "requests housekeeping complaints" },
    { title: "Request Archive", subtitle: "Archived housekeeping and complaint requests", route: :hotel_request_archive_path, keywords: "request archive archived housekeeping complaints" },
    { title: "Guest Records", subtitle: "Past and upcoming guest history", route: :hotel_guests_path, keywords: "guest records guests" },
    { title: "Room Categories", subtitle: "Manage room types", route: :hotel_room_types_path, keywords: "room categories room types" },
    { title: "Rates & Inventory", subtitle: "Rates calendar and inventory", route: :hotel_inventory_index_path, keywords: "rates inventory calendar" },
    { title: "Hotel Details", subtitle: "Property profile and public information", route: :edit_hotel_profile_path, keywords: "hotel details profile property" },
    { title: "My Profile", subtitle: "Signed-in user account profile", route: :edit_hotel_user_profile_path, keywords: "my profile user profile account" },
    { title: "Reports", subtitle: "Financial performance", route: :hotel_reports_path, keywords: "reports financial performance" },
    { title: "Night Audit", subtitle: "Close day and review blockers", route: :hotel_night_audits_path, keywords: "night audit business date day close blockers warnings" },
    { title: "Weekly Settlements", subtitle: "Payout reports", route: :payouts_hotel_reports_path, keywords: "payouts settlements weekly" },
    { title: "Daily Performance Breakdown", subtitle: "Detailed financial breakdown", route: :breakdown_hotel_reports_path, keywords: "daily performance breakdown financial reports" },
    { title: "Operation Audit Logs", subtitle: "Operational changes history", route: :hotel_audit_logs_path, keywords: "audit logs operations" },
    { title: "Inventory Audit Logs", subtitle: "Inventory and rate change history", route: :hotel_inventory_audit_logs_path, keywords: "inventory audit logs rates changes history" },
    { title: "Settings", subtitle: "Hotel and account settings", route: :hotel_settings_path, keywords: "settings preferences banking account" },
    { title: "Homepage", subtitle: "Public marketing site", route: :root_path, keywords: "homepage website home" },
    { title: "Help & Support", subtitle: "Help center guides", route: :help_center_path, keywords: "help support faq guides" }
  ].freeze

  def initialize(hotel, query)
    super(query)
    @hotel = hotel
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
      { group: "Bookings", label: "Go to bookings", url: hotel_bookings_path(@hotel) },
      { group: "Requests", label: "Go to requests", url: hotel_requests_path(@hotel) },
      { group: "Pages", label: "Go to arrival board", url: hotel_arrivals_path(@hotel) }
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
        url: hotel_portal_route(entry[:route]),
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
        url: hotel_booking_path(@hotel, booking),
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
        url: hotel_booking_path(@hotel, booking),
        score: search_score(haystack, @query) + 5
      }
    end
  end

  def hotel_portal_route(route_name)
    method = method(route_name)
    method.arity.zero? ? method.call : method.call(@hotel)
  end
end
