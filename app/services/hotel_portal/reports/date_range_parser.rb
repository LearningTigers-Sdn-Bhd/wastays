# frozen_string_literal: true

module HotelPortal
  module Reports
    class DateRangeParser
      attr_reader :date_preset

      def self.parse_date(value)
        return if value.blank?
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Parses a combined "start/end" range value (emitted by the reports
      # date-range picker) into [start_date, end_date]. Returns [nil, nil] when
      # the value is missing or malformed.
      def self.parse_date_range_param(value)
        endpoints = value.to_s.split("/", -1)
        return [ nil, nil ] unless endpoints.length == 2

        dates = endpoints.map { |endpoint| Date.iso8601(endpoint) }
        dates.all? ? dates : [ nil, nil ]
      rescue ArgumentError, TypeError
        [ nil, nil ]
      end

      def initialize(params, current_hotel = nil)
        @params = params
        @current_hotel = current_hotel
      end

      def parse_range
        preset = @params[:date_preset].presence
        preset ||= "custom" if @params[:date_range].present? || @params[:start_date].present? || @params[:end_date].present?
        preset ||= "legacy_date" if @params[:date].present?
        preset ||= "today"
        @date_preset = preset

        # Export links carry the resolved dates alongside the preset. Prefer those
        # explicit dates so relative presets cannot shift across a date boundary.
        explicit_start = self.class.parse_date(@params[:start_date])
        explicit_end = self.class.parse_date(@params[:end_date])
        if explicit_start || explicit_end
          start_date = explicit_start || explicit_end
          end_date = explicit_end || start_date
          end_date = start_date if end_date < start_date
          return [ start_date, end_date ]
        end

        if preset.present?
          case preset
          when "today"
            return [ Date.current, Date.current ]
          when "all_time"
            return [ Date.new(2024, 1, 1), Date.current ]
          when "this_year"
            return [ Date.current.beginning_of_year, Date.current.end_of_year ]
          when "last_month"
            last_month = 1.month.ago.to_date
            return [ last_month.beginning_of_month, last_month.end_of_month ]
          when "this_month"
            return [ Date.current.beginning_of_month, Date.current.end_of_month ]
          when "single"
            single_date = self.class.parse_date(@params[:start_date]) || self.class.parse_date(@params[:date]) || Date.current
            return [ single_date, single_date ]
          when "custom"
            range_start, range_end = self.class.parse_date_range_param(@params[:date_range])
            start = range_start || self.class.parse_date(@params[:start_date]) || Date.current.beginning_of_month
            end_date = range_end || self.class.parse_date(@params[:end_date]) || Date.current.end_of_month
            end_date = start if end_date < start
            return [ start, end_date ]
          when "legacy_date"
            parsed_date = self.class.parse_date(@params[:date])
            return [ parsed_date, parsed_date ] if parsed_date
          else
            if preset =~ /\A\d{4}-\d{2}\z/
              start_date = Date.parse("#{preset}-01")
              return [ start_date, start_date.end_of_month ]
            end
          end
        end

        if @params[:start_date].blank? && @params[:end_date].blank? && @params[:date].present?
          parsed_date = self.class.parse_date(@params[:date])
          return [ parsed_date, parsed_date ]
        end

        start_date = self.class.parse_date(@params[:start_date])
        end_date = self.class.parse_date(@params[:end_date])

        start_date ||= end_date || Date.current
        end_date ||= start_date
        end_date = start_date if end_date < start_date

        [ start_date, end_date ]
      end

      def parse_as_of_date
        preset = @params[:date_preset].presence
        preset ||= "custom" if @params[:as_of_date].present?
        @date_preset = preset || "today"

        if preset.present?
          case preset
          when "today"
            return Date.current
          when "all_time", "this_year"
            return Date.current
          when "last_month"
            last_month = 1.month.ago.to_date
            return last_month.end_of_month
          when "this_month"
            return Date.current.end_of_month
          when "single"
            return self.class.parse_date(@params[:start_date]) || Date.current
          when "custom"
            return self.class.parse_date(@params[:as_of_date]) || Date.current.end_of_month
          else
            if preset =~ /\A\d{4}-\d{2}\z/
              return Date.parse("#{preset}-01").end_of_month
            end
          end
        end

        fallback = self.class.parse_date(@params[:as_of_date]) || self.class.parse_date(@params[:date])
        fallback || (@current_hotel.respond_to?(:business_date_for) && @current_hotel.business_date_for) || Date.current
      end
    end
  end
end
