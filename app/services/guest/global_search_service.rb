class Guest::GlobalSearchService < BaseGlobalSearchService
  GROUP_PRIORITY = { "Bookings" => 0, "Pages" => 1 }.freeze
  PAGE_RESULTS = [
    { title: "Guest Dashboard", subtitle: "Overview and upcoming stays", route: :guest_dashboard_path, keywords: "guest dashboard overview home" },
    { title: "My Bookings", subtitle: "All your reservations", route: :guest_bookings_path, keywords: "bookings reservations stays history" },
    { title: "Refunds", subtitle: "Track and review refund requests", route: :guest_refund_requests_path, keywords: "refunds refund requests cancellations" },
    { title: "Homepage", subtitle: "Public marketing site", route: :root_path, keywords: "homepage website home" },
    { title: "Help & Support", subtitle: "Help center guides", route: :help_center_path, keywords: "help support faq guides" }
  ].freeze

  def initialize(guest, query)
    super(query)
    @guest = guest
  end

  def perform
    rows = page_results + booking_results
    rows = rows.uniq { |entry| [ entry[:title], entry[:url] ] }
    rows.sort_by { |entry| [ GROUP_PRIORITY.fetch(entry[:group], 99), -entry[:score].to_i ] }
        .first(20)
        .map { |entry| entry.except(:score) }
  end

  def quick_actions
    [
      { group: "Bookings", label: "Go to bookings", url: guest_bookings_path },
      { group: "Pages", label: "Go to refunds", url: guest_refund_requests_path },
      { group: "Pages", label: "Go to dashboard", url: guest_dashboard_path }
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
        url: send(entry[:route]),
        score: score + 10
      }
    end
  end

  def booking_results
    return [] if @query.blank?

    @guest.bookings.includes(:hotel).search(@query).order(check_in: :asc).limit(12).map do |booking|
      haystack = [
        booking.confirmation_token,
        booking.guest_name,
        booking.guest_email,
        booking.guest_phone,
        booking.hotel&.name
      ].join(" ").downcase

      {
        title: "#{booking.confirmation_token} · #{booking.hotel&.name}",
        subtitle: "#{booking.guest_name} · #{booking.check_in&.strftime('%d %b %Y')}",
        group: "Bookings",
        url: guest_booking_path(booking),
        score: search_score(haystack, @query) + 6
      }
    end
  end
end
