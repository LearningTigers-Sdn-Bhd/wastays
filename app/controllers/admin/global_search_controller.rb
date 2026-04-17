module Admin
  class GlobalSearchController < BaseController
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

    def index
      query = params[:q].to_s.strip.downcase
      results = Rails.cache.fetch(cache_key_for(query), expires_in: 2.minutes) do
        rows = page_results(query) + hotel_results(query) + booking_results(query)
        rows = rows.uniq { |entry| [ entry[:title], entry[:url] ] }
        rows.sort_by { |entry| [ GROUP_PRIORITY.fetch(entry[:group], 99), -entry[:score].to_i ] }
      end

      render json: {
        results: results.first(20).map { |entry| entry.except(:score) },
        quick_actions: quick_actions
      }
    end

    private

    def page_results(query)
      PAGE_RESULTS.filter_map do |entry|
        text = [ entry[:title], entry[:subtitle], entry[:keywords] ].join(" ").downcase
        score = search_score(text, query)
        next if query.present? && score.zero?

        {
          title: entry[:title],
          subtitle: entry[:subtitle],
          group: "Pages",
          url: resolve_url(entry),
          score: score + 10
        }
      end
    end

    def hotel_results(query)
      return [] if query.blank?

      q = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      hotels = Hotel.where("name ILIKE ?", q).order(:name).limit(12).map do |hotel|
        score = search_score(hotel.name.downcase, query)
        {
          title: hotel.name,
          subtitle: "Open hotel details",
          group: "Hotels",
          url: admin_hotel_path(hotel),
          score: score + 5
        }
      end

      list_result_score = search_score("manage hotels hotels list".downcase, query)
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

    def booking_results(query)
      return [] if query.blank?

      q = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      bookings = Booking.includes(:hotel)
                        .where("confirmation_token ILIKE :q OR guest_name ILIKE :q OR guest_email ILIKE :q OR guest_phone ILIKE :q", q: q)
                        .order(created_at: :desc)
                        .limit(10)

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
          score: search_score(haystack, query) + 6
        }
      end
    end

    def resolve_url(entry)
      base = send(entry[:url])
      entry[:anchor].present? ? "#{base}##{entry[:anchor]}" : base
    end

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

    def cache_key_for(query)
      "admin:global_search:v5:user:#{current_user.id}:q:#{Digest::SHA256.hexdigest(query)}"
    end

    def quick_actions
      [
        { group: "Bookings", label: "Go to bookings", url: admin_bookings_path },
        { group: "Hotels", label: "Go to hotels", url: admin_hotels_path },
        { group: "Pages", label: "Go to dashboard", url: admin_dashboard_path }
      ]
    end
  end
end
