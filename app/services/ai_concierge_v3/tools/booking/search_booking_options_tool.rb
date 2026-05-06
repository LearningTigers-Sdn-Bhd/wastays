module AiConciergeV3
  module Tools
    module Booking
      class SearchBookingOptionsTool
        MAX_ROOM_TYPES = 3
        MAX_OPTIONS_PER_ROOM_TYPE = 3
        WINDOW_DAYS = {
          "early" => 1..10,
          "mid" => 11..20
        }.freeze

        def initialize(hotel:, target_month:, target_year:, month_segment:, check_in: nil, check_out: nil, adults:, children:, room_count:, nights: 2)
          @hotel = hotel
          @target_month = target_month.to_i
          @target_year = target_year.to_i
          @month_segment = month_segment
          @check_in = parse_date(check_in)
          @check_out = parse_date(check_out)
          @adults = adults.to_i
          @children = children.to_i
          @room_count = room_count.to_i
          @nights = nights.to_i.positive? ? nights.to_i : 2
        end

        def call
          grouped_options.first(MAX_ROOM_TYPES)
        end

        private

        attr_reader :hotel, :target_month, :target_year, :month_segment, :check_in, :check_out, :adults, :children, :room_count, :nights

        def grouped_options
          hotel.room_types.order(:id).each_with_object([]) do |room_type, groups|
            options = options_for_room_type(room_type)
            next if options.empty?

            groups << {
              "room_type_id" => room_type.id,
              "room_type_name" => room_type.name,
              "options" => options.each_with_index.map do |option, index|
                option.merge(
                  "position" => index + 1,
                  "selection_id" => selection_id(room_type.id, index + 1)
                )
              end
            }
          end
        end

        def options_for_room_type(room_type)
          return explicit_range_options_for(room_type) if explicit_range?

          window_options_for(room_type)
        end

        def explicit_range?
          check_in.present? && check_out.present?
        end

        def explicit_range_options_for(room_type)
          return [] unless room_type_available?(room_type, check_in: check_in, check_out: check_out)

          [ build_option(room_type, check_in: check_in, check_out: check_out) ]
        end

        def window_options_for(room_type)
          options = []

          # 1. Try to fill with best_window_dates first to align options across room types
          best_window_dates.each do |candidate|
            candidate_check_out = candidate + nights.days
            next unless room_type_available?(room_type, check_in: candidate, check_out: candidate_check_out)

            options << build_option(room_type, check_in: candidate, check_out: candidate_check_out)
          end

          # 2. Fill remaining slots with earliest available dates not already included
          if options.size < MAX_OPTIONS_PER_ROOM_TYPE
            used_dates = options.map { |o| Date.parse(o["check_in"]) }

            candidate_check_in_days.each do |candidate|
              break if options.size >= MAX_OPTIONS_PER_ROOM_TYPE
              next if used_dates.include?(candidate)

              candidate_check_out = candidate + nights.days
              next unless candidate_check_out.month == target_month || month_segment.blank?
              next unless room_type_available?(room_type, check_in: candidate, check_out: candidate_check_out)

              options << build_option(room_type, check_in: candidate, check_out: candidate_check_out)
            end
          end

          options.sort_by { |o| o["check_in"] }
        end

        def best_window_dates
          @best_window_dates ||= begin
            date_scores = candidate_check_in_days.filter_map do |candidate|
              candidate_check_out = candidate + nights.days
              next unless candidate_check_out.month == target_month || month_segment.blank?

              count = hotel.room_types.count { |rt| room_type_available?(rt, check_in: candidate, check_out: candidate_check_out) }
              next if count.zero?

              [ candidate, count ]
            end

            sorted_dates = date_scores.sort_by { |candidate, score| [ -score, candidate ] }
            sorted_dates.first(MAX_OPTIONS_PER_ROOM_TYPE).map(&:first).sort
          end
        end

        def candidate_check_in_days
          start_day, end_day = date_range_bounds
          (start_day..end_day).map { |day| Date.new(target_year, target_month, day) }
        end

        def date_range_bounds
          if month_segment == "late"
            [ 21, Date.new(target_year, target_month, -1).day ]
          elsif WINDOW_DAYS.key?(month_segment)
            range = WINDOW_DAYS.fetch(month_segment)
            [ range.begin, range.end ]
          else
            [ 1, Date.new(target_year, target_month, -1).day ]
          end
        end

        def room_type_available?(room_type, check_in:, check_out:)
          return false if room_type.max_adults < adults

          stay_dates = (check_in...check_out).to_a
          return false if stay_dates.empty?

          inventories = room_type.room_inventories.where(date: stay_dates)
          return false unless inventories.count == stay_dates.count
          return false unless inventories.all? { |inv| inv.status == "open" && inv.quantity >= room_count }

          rates = room_type.room_rates.where(date: stay_dates)
          return false unless rates.count == stay_dates.count

          true
        end

        def build_option(room_type, check_in:, check_out:)
          stay_dates = (check_in...check_out).to_a
          total_price = room_type.room_rates.where(date: stay_dates).sum(:price) * room_count

          {
            "room_type_id" => room_type.id,
            "room_type_name" => room_type.name,
            "check_in" => check_in.iso8601,
            "check_out" => check_out.iso8601,
            "nights" => (check_out - check_in).to_i,
            "total_price" => total_price,
            "currency" => room_type.room_rates.where(date: check_in...check_out).first&.currency || "MYR",
            "adults" => adults,
            "children" => children,
            "room_count" => room_count
          }
        end

        def parse_date(value)
          return value if value.is_a?(Date)
          return if value.blank?

          Date.parse(value.to_s)
        rescue Date::Error
          nil
        end

        def selection_id(room_type_id, position)
          "room_type_#{room_type_id}_option_#{position}"
        end
      end
    end
  end
end
