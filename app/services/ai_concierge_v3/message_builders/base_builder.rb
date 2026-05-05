module AiConciergeV3
  module MessageBuilders
    class BaseBuilder
      def initialize(hotel:, context:)
        @hotel = hotel
        @context = context
      end

      private

      attr_reader :hotel, :context

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

      def format_price(currency, amount)
        [display_currency(currency), format("%.2f", amount.to_f)].join(" ")
      end

      def format_option_price(currency, amount)
        format_price(currency, amount)
      end

      def display_currency(currency)
        value = currency.presence || hotel.try(:default_currency) || "MYR"
        value == "MYR" ? "RM" : value
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

      def option_group_lines(group)
        return "" unless group.is_a?(Hash)

        lines = Array(group["options"]).map do |option|
          "#{option['position']}. #{format_option_price(option['currency'], option['total_price'])} : Check-in *#{format_date(option['check_in'])}* - Check-out *#{format_date(option['check_out'])}*"
        end

        [group["room_type_name"], lines.join("\n")].join("\n")
      end
    end
  end
end
