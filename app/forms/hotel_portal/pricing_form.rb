# frozen_string_literal: true

module HotelPortal
  class PricingForm
    include ActiveModel::Model

    HolidayFormRow = Struct.new(:id, :name, :start_date, :end_date, :price, :persisted?, keyword_init: true)

    attr_accessor :general_rule, :weekends_rule, :walk_in_rule, :corporate_rule, :ota_rule, :pricing_data, :weekend_days,
                  :public_holiday_rows, :school_holiday_rows, :selected_room_type_ids, :errors

    def initialize(hotel, room_types)
      @hotel = hotel
      @room_types = room_types
      @errors = {}
    end

    def from_saved_rules(selected_ids = nil)
      @selected_room_type_ids = if selected_ids.nil?
        @room_types.map(&:id)
      else
        Array(selected_ids).reject(&:blank?).map(&:to_i)
      end

      # Load saved rules into pricing_data
      rules = @hotel.pricing_rules.to_a
      @general_rule = rules.find { |r| r.rule_type == "general" }
      @weekends_rule = rules.find { |r| r.rule_type == "weekends" }
      @walk_in_rule = rules.find { |r| r.rule_type == "walk_in" }
      @corporate_rule = rules.find { |r| r.rule_type == "corporate_rate" }
      @ota_rule = rules.find { |r| r.rule_type == "ota_rate" }

      @pricing_data = {
        gp_price: @general_rule&.price,
        gp_start_date: @general_rule&.start_date,
        gp_end_date: @general_rule&.end_date,
        wk_price: @weekends_rule&.price,
        wk_start_date: @weekends_rule&.start_date,
        wk_end_date: @weekends_rule&.end_date,
        wi_price: @walk_in_rule&.price,
        wi_start_date: @walk_in_rule&.start_date,
        wi_end_date: @walk_in_rule&.end_date,
        cr_price: @corporate_rule&.price,
        cr_start_date: @corporate_rule&.start_date,
        cr_end_date: @corporate_rule&.end_date,
        ota_price: @ota_rule&.price,
        ota_start_date: @ota_rule&.start_date,
        ota_end_date: @ota_rule&.end_date
      }

      @weekend_days = @weekends_rule&.weekdays.presence || [ 5, 6, 0 ]
      @public_holiday_rows = @hotel.pricing_rules.public_holidays.order(:start_date, :name).map { |rule| row_from_record(rule) }
      @public_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @public_holiday_rows.empty?

      @school_holiday_rows = @hotel.pricing_rules.where(rule_type: "school_holiday").order(:start_date, :name).map { |rule| row_from_record(rule) }
      @school_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @school_holiday_rows.empty?

      self
    end

    def pricing_rules_count
      @hotel.pricing_rules.count
    end

    def from_params(params)
      @general_rule = nil
      @weekends_rule = nil
      @walk_in_rule = nil
      @corporate_rule = nil
      @ota_rule = nil

      @pricing_data = {
        gp_price: params[:gp_price],
        gp_start_date: params[:gp_start_date],
        gp_end_date: params[:gp_end_date],
        wk_price: params[:wk_price],
        wk_start_date: params[:wk_start_date],
        wk_end_date: params[:wk_end_date],
        wi_price: params[:wi_price],
        wi_start_date: params[:wi_start_date],
        wi_end_date: params[:wi_end_date],
        cr_price: params[:cr_price],
        cr_start_date: params[:cr_start_date],
        cr_end_date: params[:cr_end_date],
        ota_price: params[:ota_price],
        ota_start_date: params[:ota_start_date],
        ota_end_date: params[:ota_end_date]
      }

      @weekend_days = Array(params[:weekend_days]).reject(&:blank?).map(&:to_i)
      @weekend_days = [ 5, 6, 0 ] if @weekend_days.empty?

      @selected_room_type_ids = Array(params[:room_type_ids]).reject(&:blank?).map(&:to_i)
      @selected_room_type_ids = @room_types.map(&:id) if @selected_room_type_ids.empty?

      @public_holiday_rows = Array(params[:public_holidays]).map { |row| row_from_hash(row) }
      @public_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @public_holiday_rows.empty?

      @school_holiday_rows = Array(params[:school_holidays]).map { |row| row_from_hash(row) }
      @school_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @school_holiday_rows.empty?

      self
    end

    private

    def row_from_record(rule)
      HolidayFormRow.new(
        id: rule.id,
        name: rule.name,
        start_date: rule.start_date,
        end_date: rule.end_date,
        price: rule.price,
        persisted?: true
      )
    end

    def row_from_hash(row)
      row = row.to_h.symbolize_keys
      HolidayFormRow.new(
        id: nil,
        name: row[:name],
        start_date: row[:start_date],
        end_date: row[:end_date],
        price: row[:price],
        persisted?: false
      )
    end
  end
end
