# frozen_string_literal: true

class HotelPortal::GlobalSearchService < BaseGlobalSearchService
  GROUP_PRIORITY = { "Bookings" => 0, "Pages" => 1, "Requests" => 2 }.freeze
  # Every page carries the layer that owns it and the permission that guards it.
  # The layer decides whether a hit opens here or in a new tab -- the palette is
  # the only way to cross a layer boundary without using the sidebar, so it has
  # to make the same choice the sidebar does. The permission decides whether the
  # page is offered at all: without it the palette happily pointed people at
  # pages their role cannot open.
  PAGE_RESULTS = [
    { title: "Hotel Dashboard", subtitle: "Overview and recent activity", route: :hotel_dashboard_path, keywords: "dashboard overview recent bookings", layer: :operations, permission: "view_bookings" },
    { title: "Front Desk", subtitle: "Arrivals, in-house guests, and departures", route: :hotel_front_desk_path, keywords: "front desk arrival board arrivals check in in house guests departures today check outs checked out", layer: :operations, permission: [ "view_bookings", "manage_guest_arrival" ] },
    { title: "Stay View", subtitle: "Timeline planning and room operations", route: :hotel_stay_view_path, keywords: "stay view booking timeline board calendar tape chart room status housekeeping assignment planning operations", layer: :operations, permission: [ "view_bookings", "manage_bookings", "view_room_readiness", "manage_room_status" ] },
    { title: "Folios", subtitle: "Guest folios, balances, and refund due review", route: :hotel_folios_path, keywords: "folios ledger balances balance due refund due finance", layer: :financials, permission: "view_bookings" },
    { title: "Requests", subtitle: "Housekeeping, complaints, and the archive", route: :hotel_requests_path, keywords: "requests housekeeping complaints checkout archive archived", layer: :operations, permission: "manage_requests" },
    { title: "Guest Records", subtitle: "Past and upcoming guest history", route: :hotel_guests_path, keywords: "guest records guests", layer: :operations, permission: "view_guest_records" },
    { title: "Room Categories", subtitle: "Manage room types", route: :hotel_room_types_path, keywords: "room categories room types", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Rates & Inventory", subtitle: "Rates calendar and inventory", route: :hotel_inventory_index_path, keywords: "rates inventory calendar", layer: :operations, permission: "manage_hotel_profile" },
    { title: "Hotel Details", subtitle: "Property profile and public information", route: :edit_hotel_profile_path, keywords: "hotel details profile property", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Taxes & Fees", subtitle: "Booking tax and fee settings", route: :hotel_taxes_fees_path, keywords: "taxes fees tourism tax sst service charge", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Nearby Attractions", subtitle: "Local recommendations for guests", route: :hotel_nearby_attractions_path, keywords: "nearby attractions places around property guest content", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Banking", subtitle: "Banking and payout account settings", route: :hotel_banking_details_settings_path, keywords: "banking finance payout account", layer: :settings, permission: "manage_account" },
    { title: "Room Revenue", subtitle: "Room tax rules and reservation policies", route: :hotel_room_revenue_path, keywords: "room revenue tax rules late checkout early departure no show cancellation policy", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Transaction Code Reference", subtitle: "Read-only list of posting codes", route: :hotel_transaction_code_references_path, keywords: "transaction codes posting accounting finance reference", layer: :settings, permission: "manage_hotel_profile" },
    { title: "General Ledger Mappings", subtitle: "Map transaction codes to ledger accounts", route: :hotel_general_ledger_maps_path, keywords: "general ledger mappings accounting finance", layer: :settings, permission: "manage_general_ledger_maps" },
    { title: "AI Concierge", subtitle: "AI concierge configuration", route: :hotel_ai_concierge_settings_path, keywords: "ai concierge guest content", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Policies", subtitle: "Property policies for AI concierge", route: :hotel_knowledge_policies_path, keywords: "policy policies property rules regulations", plan_feature: "ai_concierge_page", layer: :settings, permission: "manage_hotel_profile" },
    { title: "FAQs", subtitle: "Frequently asked questions for AI concierge", route: :hotel_knowledge_faqs_path, keywords: "faq faqs frequently asked questions answers", plan_feature: "ai_concierge_page", layer: :settings, permission: "manage_hotel_profile" },
    { title: "General Info", subtitle: "General property information for AI concierge", route: :hotel_knowledge_general_infos_path, keywords: "general info information property hotel", plan_feature: "ai_concierge_page", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Knowledge Diagnostics", subtitle: "Review AI concierge knowledge gaps", route: :hotel_knowledge_diagnostics_path, keywords: "knowledge diagnostics ai concierge gaps", plan_feature: "ai_concierge_page", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Notifications", subtitle: "Notification settings", route: :hotel_notification_settings_path, keywords: "notifications guest content settings", layer: :settings, permission: "manage_hotel_profile" },
    { title: "Staff Management", subtitle: "Manage hotel staff access", route: :hotel_users_path, keywords: "staff management users team", layer: :settings, permission: "manage_users" },
    { title: "Roles & Permissions", subtitle: "Configure role-based access", route: :hotel_roles_path, keywords: "roles permissions team access", plan_feature: "role_based_access_control", layer: :settings, permission: "manage_users" },
    { title: "My Profile", subtitle: "Signed-in user account profile", route: :edit_hotel_user_profile_path, keywords: "my profile user profile account", layer: :settings },
    { title: "Reports", subtitle: "Financial performance", route: :hotel_reports_path, keywords: "reports financial performance", layer: :reports, permission: "view_reports" },
    { title: "Run Night Audit", subtitle: "Verify readiness and close the business date", route: :hotel_night_audit_run_path, keywords: "run night audit business date day close blockers warnings", layer: :operations, permission: "manage_night_audit" },
    { title: "Payouts", subtitle: "Payout reports", route: :payouts_hotel_reports_path, keywords: "payouts settlements weekly", layer: :reports, permission: "view_reports" },
    { title: "Daily Performance Breakdown", subtitle: "Detailed financial breakdown", route: :breakdown_hotel_reports_path, keywords: "daily performance breakdown financial reports", layer: :reports, permission: "view_reports" },
    { title: "Operation Logs", subtitle: "Operational changes history", route: :hotel_audit_logs_path, keywords: "audit logs operation logs operations", plan_feature: "full_audit_trail", layer: :reports, permission: "view_audit_logs" },
    { title: "Notification Logs", subtitle: "Notification delivery attempts and failures", route: :hotel_notification_logs_path, keywords: "notification logs whatsapp email delivery failed sent pending", layer: :reports, permission: "view_audit_logs" },
    { title: "Inventory Audit Logs", subtitle: "Inventory and rate change history", route: :hotel_inventory_audit_logs_path, keywords: "inventory audit logs rates changes history", layer: :reports, permission: "view_audit_logs" },
    { title: "Plan & Billing", subtitle: "Subscription and billing settings", route: :hotel_plan_path, keywords: "plan billing subscription features upgrade", layer: :settings },
    { title: "Settings", subtitle: "Hotel and account settings", route: :hotel_general_settings_path, keywords: "settings preferences banking account", layer: :settings, permission: [ "manage_hotel_profile", "manage_account" ] },
    { title: "Homepage", subtitle: "Public marketing site", route: :root_path, keywords: "homepage website home" },
    { title: "Help & Support", subtitle: "Help center guides", route: :help_center_path, keywords: "help support faq guides" }
  ].freeze

  def initialize(hotel, query, user: nil, layer: :operations)
    super(query)
    @hotel = hotel
    @user = user
    @layer = layer
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
      { group: "Bookings", label: "Go to reservations", url: hotel_front_desk_path(@hotel, tab: "bookings", view: "list") },
      { group: "Pages", label: "Go to folios", url: hotel_folios_path(@hotel) },
      { group: "Requests", label: "Go to requests", url: hotel_requests_path(@hotel) },
      { group: "Pages", label: "Go to front desk", url: hotel_front_desk_path(@hotel) }
    ]
  end

  private

  def page_results
    PAGE_RESULTS.filter_map do |entry|
      next if entry[:plan_feature].present? && !@hotel.feature_enabled?(entry[:plan_feature])
      next unless permitted?(entry[:permission])

      text = [ entry[:title], entry[:subtitle], entry[:keywords] ].join(" ").downcase
      score = search_score(text, @query)
      next if @query.present? && score.zero?

      {
        title: entry[:title],
        subtitle: entry[:subtitle],
        group: "Pages",
        url: hotel_portal_route(entry[:route]),
        external: crosses_layer?(entry[:layer]),
        score: score + 10
      }
    end
  end

  # Mirrors the sidebar's own check: a hotel-scoped grant or an account-wide one.
  # With no user in hand the palette behaves as it always did and filters nothing.
  def permitted?(permission)
    return true if permission.blank? || @user.nil?

    Array(permission).any? do |slug|
      @user.has_permission?(slug, hotel: @hotel) || @user.has_permission?(slug)
    end
  end

  # Pages outside the current layer open in a new tab, the same as the layer
  # doors in the sidebar. Pages with no layer of their own -- the marketing site,
  # the help centre -- keep opening in place.
  def crosses_layer?(layer)
    layer.present? && layer != @layer
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
        url: hotel_booking_workspace_path(@hotel, booking, tab: "booking_details"),
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
        url: hotel_booking_workspace_path(@hotel, booking, tab: "booking_details"),
        score: search_score(haystack, @query) + 5
      }
    end
  end

  def hotel_portal_route(route_name)
    return public_send(route_name) if route_name.in?([ :root_path, :help_center_path ])

    public_send(route_name, @hotel)
  end
end
