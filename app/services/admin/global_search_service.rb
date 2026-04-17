class Admin::GlobalSearchService < BaseGlobalSearchService
  GROUP_PRIORITY = { "Bookings" => 0, "Pages" => 1, "Hotels" => 2 }.freeze
  PAGE_RESULTS = [
    { title: "Dashboard", subtitle: "Admin dashboard overview", url: :admin_dashboard_path, keywords: "dashboard overview" },
    { title: "Recent Successful Bookings", subtitle: "Dashboard section", url: :admin_dashboard_path, anchor: "recent-successful-bookings", keywords: "recent bookings successful bookings" },
    { title: "Revenue & Margin Analytics", subtitle: "Performance analytics", url: :admin_analytics_path, keywords: "analytics revenue margin reports" },
    { title: "Manage Hotels", subtitle: "Hotels list", url: :admin_hotels_path, keywords: "hotels manage hotels list" },
    { title: "Platform Bookings", subtitle: "All bookings", url: :admin_bookings_path, keywords: "bookings recent bookings" },
    { title: "Payment Issues", subtitle: "Reconciliation queue", url: :admin_reconciliation_dashboard_path, keywords: "reconciliation payment issues webhooks" },
    { title: "Payout Batches", subtitle: "Weekly settlements", url: :admin_payout_batches_path, keywords: "payout settlements batches" },
    { title: "Margin Settings", subtitle: "Platform margin rules", url: :admin_margin_rules_path, keywords: "margin rules settings" },
    { title: "Setup Fee Settings", subtitle: "Setup fee rules", url: :admin_setup_fee_rules_path, keywords: "setup fee rules settings" },
    { title: "Audit Logs", subtitle: "System activity", url: :admin_audit_logs_path, keywords: "audit logs activity" },
    { title: "API Access Management", subtitle: "API keys", url: :admin_api_keys_path, keywords: "api access keys integration" }
  ].freeze

  def perform
    rows = page_results + hotel_results + booking_results
    rows = rows.uniq { |entry| [ entry[:title], entry[:url] ] }
    rows.sort_by { |entry| [ GROUP_PRIORITY.fetch(entry[:group], 99), -entry[:score].to_i ] }
        .first(20)
        .map { |entry| entry.except(:score) }
  end

  def quick_actions
    [
      { group: "Bookings", label: "Go to bookings", url: admin_bookings_path },
      { group: "Hotels", label: "Go to hotels", url: admin_hotels_path },
      { group: "Pages", label: "Go to dashboard", url: admin_dashboard_path }
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
        url: resolve_url(entry),
        score: score + 10
      }
    end
  end

  def hotel_results
    return [] if @query.blank?

    hotels = Hotel.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%").order(:name).limit(12).map do |hotel|
      score = search_score(hotel.name.downcase, @query)
      {
        title: hotel.name,
        subtitle: "Open hotel details",
        group: "Hotels",
        url: admin_hotel_path(hotel),
        score: score + 5
      }
    end

    list_result_score = search_score("manage hotels hotels list".downcase, @query)
    list_result = if list_result_score.positive?
      [ {
        title: "Manage Hotels",
        subtitle: "Open hotels list",
        group: "Hotels",
        url: admin_hotels_path,
        score: list_result_score + 4
      } ]
    else
      []
    end

    (list_result + hotels).sort_by { |entry| -entry[:score] }.first(8)
  end

  def booking_results
    return [] if @query.blank?

    bookings = Booking.includes(:hotel).search(@query).order(created_at: :desc).limit(10)

    bookings.map do |booking|
      haystack = [
        booking.confirmation_token,
        booking.guest_name,
        booking.guest_email,
        booking.guest_phone,
        booking.hotel&.name
      ].join(" ").downcase

      {
        title: "#{booking.confirmation_token} · #{booking.guest_name}",
        subtitle: "#{booking.hotel&.name} · #{booking.guest_email}",
        group: "Bookings",
        url: admin_booking_path(booking),
        score: search_score(haystack, @query) + 6
      }
    end
  end

  def resolve_url(entry)
    base = send(entry[:url])
    entry[:anchor].present? ? "#{base}##{entry[:anchor]}" : base
  end
end
