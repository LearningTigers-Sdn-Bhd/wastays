module HotelOps
  class SyncPricingRules
    def initialize(hotel:, gp_price:, gp_start_date:, gp_end_date:, wk_price:, wk_start_date:, wk_end_date:, weekend_days:, school_holidays:, wi_price: nil, wi_start_date: nil, wi_end_date: nil, cr_price: nil, cr_start_date: nil, cr_end_date: nil, ota_price: nil, ota_start_date: nil, ota_end_date: nil, public_holidays:)
      @hotel = hotel
      @gp_price = decimal_or_nil(gp_price)
      @gp_start_date = date_or_nil(gp_start_date)
      @gp_end_date = date_or_nil(gp_end_date) || @gp_start_date
      @wk_price = decimal_or_nil(wk_price)
      @wk_start_date = date_or_nil(wk_start_date)
      @wk_end_date = date_or_nil(wk_end_date) || @wk_start_date
      @weekend_days = Array(weekend_days).reject(&:blank?).map(&:to_i).uniq
      @school_holidays = Array(school_holidays)
      @wi_price = decimal_or_nil(wi_price)
      @wi_start_date = date_or_nil(wi_start_date)
      @wi_end_date = date_or_nil(wi_end_date) || @wi_start_date
      @cr_price = decimal_or_nil(cr_price)
      @cr_start_date = date_or_nil(cr_start_date)
      @cr_end_date = date_or_nil(cr_end_date) || @cr_start_date
      @ota_price = decimal_or_nil(ota_price)
      @ota_start_date = date_or_nil(ota_start_date)
      @ota_end_date = date_or_nil(ota_end_date) || @ota_start_date
      @public_holidays = Array(public_holidays)
    end

    def call
      @errors = { base: [], public_holidays: {} }
      rows = build_rows
      if rows.empty?
        @errors[:base] << "Add at least one pricing rule before applying."
        raise ArgumentError, "At least one pricing rule is required."
      end

      # Capture the current range before we delete anything
      old_start = @hotel.pricing_rules.minimum(:start_date)
      old_end = @hotel.pricing_rules.maximum(:end_date)

      ActiveRecord::Base.transaction do
        @hotel.pricing_rules.delete_all

        rows.each do |row|
          @hotel.pricing_rules.create!(row)
        end
      end

      new_start = rows.map { |row| row[:start_date] }.compact.min
      new_end = rows.map { |row| row[:end_date] }.compact.max

      # The union of old and new ranges ensures we clean up moved/deleted rules
      apply_start = [ old_start, new_start ].compact.min
      apply_end = [ old_end, new_end ].compact.max

      { success: true, apply_start_date: apply_start, apply_end_date: apply_end }
    rescue => e
      { success: false, error: e.message, errors: @errors || {} }
    end

    private

    def build_rows
      rows = []

      if @gp_price
        if @gp_start_date.blank?
          @errors[:base] << "General pricing requires a start date."
          raise ArgumentError, "General pricing requires a start date."
        end
        if @gp_end_date < @gp_start_date
          @errors[:base] << "General pricing end date cannot be earlier than start date."
          raise ArgumentError, "General pricing end date cannot be earlier than start date."
        end

        rows << {
          rule_type: "general",
          name: "General",
          price: @gp_price,
          start_date: @gp_start_date,
          end_date: @gp_end_date
        }
      end

      if @wk_price
        if @wk_start_date.blank?
          @errors[:base] << "Weekends pricing requires a start date."
          raise ArgumentError, "Weekends pricing requires a start date."
        end
        if @wk_end_date < @wk_start_date
          @errors[:base] << "Weekends pricing end date cannot be earlier than start date."
          raise ArgumentError, "Weekends pricing end date cannot be earlier than start date."
        end

        rows << {
          rule_type: "weekends",
          name: "Weekends",
          price: @wk_price,
          start_date: @wk_start_date,
          end_date: @wk_end_date,
          weekdays: @weekend_days
        }
      end

      if @wi_price
        if @wi_start_date.blank?
          @errors[:base] << "Walk-in pricing requires a start date."
          raise ArgumentError, "Walk-in pricing requires a start date."
        end
        if @wi_end_date < @wi_start_date
          @errors[:base] << "Walk-in pricing end date cannot be earlier than start date."
          raise ArgumentError, "Walk-in pricing end date cannot be earlier than start date."
        end

        rows << {
          rule_type: "walk_in",
          name: "Walk-in",
          price: @wi_price,
          start_date: @wi_start_date,
          end_date: @wi_end_date
        }
      end

      if @cr_price
        if @cr_start_date.blank?
          @errors[:base] << "Corporate rate requires a start date."
          raise ArgumentError, "Corporate rate requires a start date."
        end
        if @cr_end_date < @cr_start_date
          @errors[:base] << "Corporate rate end date cannot be earlier than start date."
          raise ArgumentError, "Corporate rate end date cannot be earlier than start date."
        end

        rows << {
          rule_type: "corporate_rate",
          name: "Corporate Rate",
          price: @cr_price,
          start_date: @cr_start_date,
          end_date: @cr_end_date
        }
      end

      if @ota_price
        if @ota_start_date.blank?
          @errors[:base] << "OTA rate requires a start date."
          raise ArgumentError, "OTA rate requires a start date."
        end
        if @ota_end_date < @ota_start_date
          @errors[:base] << "OTA rate end date cannot be earlier than start date."
          raise ArgumentError, "OTA rate end date cannot be earlier than start date."
        end

        rows << {
          rule_type: "ota_rate",
          name: "OTA Rate",
          price: @ota_price,
          start_date: @ota_start_date,
          end_date: @ota_end_date
        }
      end

      rows.concat(normalized_school_holiday_rows)
      rows.concat(normalized_public_holiday_rows)
      rows
    end

    def normalized_school_holiday_rows
      @school_holidays.each_with_index.filter_map do |holiday, index|
        row = holiday.to_h.symbolize_keys
        name = row[:name].to_s.strip.presence || "School Holiday"
        price = decimal_or_nil(row[:price])
        start_date = date_or_nil(row[:start_date])
        end_date = date_or_nil(row[:end_date]) || start_date

        next if price.blank? && start_date.blank? && end_date.blank?

        if price.blank? || start_date.blank?
          @errors[:base] << "School holiday entries must include a price and start date."
          raise ArgumentError, "School holiday entries must include a price and start date."
        end

        if end_date < start_date
          @errors[:base] << "School holiday end date cannot be earlier than start date."
          raise ArgumentError, "School holiday end date cannot be earlier than start date."
        end

        {
          rule_type: "school_holiday",
          name: name,
          price: price,
          start_date: start_date,
          end_date: end_date
        }
      end
    end

    def normalized_public_holiday_rows
      @public_holidays.each_with_index.filter_map do |holiday, index|
        row = holiday.to_h.symbolize_keys
        name = row[:name].to_s.strip
        price = decimal_or_nil(row[:price])
        start_date = date_or_nil(row[:start_date])
        end_date = date_or_nil(row[:end_date]) || start_date

        next if name.blank? && price.blank? && start_date.blank? && end_date.blank?

        if name.blank? || price.blank? || start_date.blank?
          @errors[:public_holidays][index] = "Holiday name, date, and price are required."
          raise ArgumentError, "Public holiday entries must include name, date, and price."
        end

        if end_date < start_date
          @errors[:public_holidays][index] = "End date cannot be earlier than date."
          raise ArgumentError, "Public holiday end date cannot be earlier than start date."
        end

        {
          rule_type: "public_holiday",
          name: name,
          price: price,
          start_date: start_date,
          end_date: end_date
        }
      end
    end

    def decimal_or_nil(value)
      value.present? ? BigDecimal(value.to_s) : nil
    end

    def date_or_nil(value)
      value.present? ? value.to_date : nil
    rescue ArgumentError
      nil
    end
  end
end
