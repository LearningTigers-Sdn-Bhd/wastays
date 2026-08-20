module AiConcierge
  module MessageBuilders
    class BaseBuilder
      include Rails.application.routes.url_helpers

      def initialize(hotel:, context:)
        @hotel = hotel
        @context = context
      end

      private

      attr_reader :hotel, :context

      # The branch the turn ran on. The orchestrator used to render these three
      # labels itself and pass the strings down, which put forty lines of
      # presentation inside a class whose job is deciding what happens next --
      # and next to `format_date_range` and `format_price`, which were already
      # here. It passes the branch now; the sentences are written where every
      # other sentence is written.
      def branch = context[:branch] || {}

      def month_label
        month = branch["target_month"]
        year = branch["target_year"]
        return if month.blank? || year.blank?

        [ branch["month_segment"].presence, Date::MONTHNAMES[month.to_i], year ].compact.join(" ")
      end

      def guest_label
        adults = branch["adults"].to_i
        children = branch["children"].to_i
        parts = []
        parts << "#{adults} adult#{'s' unless adults == 1}" if adults.positive?
        parts << "#{children} child#{'ren' unless children == 1}" if children.positive?
        parts.join(" and ").presence
      end

      def date_range_label
        clarification = branch["clarification_needed"]
        return unless clarification.is_a?(Hash)

        start_day = clarification["start_day"]
        end_day = clarification["end_day"]
        [ start_day, end_day ].all?(&:present?) ? "#{start_day}-#{end_day}" : nil
      end

      def format_date(value)
        return value.to_s if value.blank?

        Date.parse(value.to_s).strftime("%B %-d")
      rescue Date::Error
        value.to_s
      end

      def format_date_range(check_in, check_out)
        return "your selected stay" if check_in.blank? || check_out.blank?

        "#{format_date(check_in)} to #{format_date(check_out)}"
      end

      def format_full_date(value)
        return value.to_s if value.blank?

        Date.parse(value.to_s).strftime("%-d %B %Y")
      rescue Date::Error
        value.to_s
      end

      def format_full_date_range(check_in, check_out)
        return "your selected stay" if check_in.blank? || check_out.blank?

        "#{format_full_date(check_in)} - #{format_full_date(check_out)}"
      end

      # The same money the rest of the app prints, so a price read in a chat
      # and the same price read in the portal are not written two ways.
      #
      # `to_f` rather than the raw value: a missing price is nothing to say "-"
      # about here, where every caller has already decided it has a price worth
      # printing.
      def format_price(currency, amount)
        CurrencyFormatter.format(amount.to_f, currency: currency_code(currency))
      end

      def format_option_price(currency, amount)
        format_price(currency, amount)
      end

      def currency_code(currency)
        currency.presence || hotel.try(:default_currency) || "MYR"
      end

      def format_time(value)
        return value.to_s if value.blank?

        Time.zone.parse(value.to_s).strftime("%-I:%M %p")
      rescue ArgumentError
        value.to_s
      end

      def join_names(names)
        Array(names).uniq.to_sentence(two_words_connector: " and ", last_word_connector: ", and ")
      end

      def public_hotel_url(search_params)
        hotel_url(search_params.compact.merge(id: hotel, host: default_host))
      end

      def default_host
        host_options = Rails.application.config.action_mailer.default_url_options || {}
        protocol = host_options[:protocol].presence || "http"
        host = host_options[:host].presence || "example.com"
        port = host_options[:port].presence
        [ "#{protocol}://#{host}", port ].compact.join(port ? ":" : "")
      end

      # `rates: :from` shows one cheapest-price line instead of every plan, so
      # the catalogue grows as rooms + rates rather than rooms x rates. The
      # plans themselves come back once a room is chosen.
      # One numbered row per option, across every room type.
      #
      # The dates are written on the row only when the catalogue holds more
      # than one stay to choose between. A search for exact dates gives every
      # room the same three nights, already stated in the summary line above,
      # and repeating them under each room says nothing the guest has not just
      # read.
      def option_catalogue_lines(groups)
        options = catalogue_options(groups)
        return "" if options.empty?

        with_dates = distinct_stays(options).many?
        options.map { |option| option_row(option, with_dates: with_dates) }.join("\n")
      end

      def option_row(option, with_dates:)
        parts = [ "*#{option['position']}. #{option['room_type_name']}*" ]
        parts << format_date_range(option["check_in"], option["check_out"]) if with_dates
        [ parts.join(" · "), from_price(option) ].compact.join(" — ")
      end

      def catalogue_options(groups)
        Array(groups).flat_map do |group|
          next [] unless group.is_a?(Hash)

          Array(group["options"]).map { |option| option.merge("room_type_name" => group["room_type_name"]) }
        end
      end

      def distinct_stays(options)
        options.map { |option| [ option["check_in"], option["check_out"] ] }.uniq
      end

      # The cheapest rate plan, named as a floor rather than a price: which
      # plan it is becomes a question of its own once a room is chosen, so the
      # catalogue does not open it.
      def from_price(option)
        rate_plans = Array(option["rate_plans"]).select { |rp| rp["total_price"].present? }
        cheapest = rate_plans.min_by { |rp| rp["total_price"].to_f }

        price = cheapest&.dig("total_price") || option["total_price"]
        return if price.blank?

        "from #{format_option_price(cheapest&.dig('currency') || option['currency'], price)}"
      end
    end
  end
end
