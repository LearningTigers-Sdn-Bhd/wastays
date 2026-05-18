# frozen_string_literal: true

module HotelPortal
  class PricingForm
    include ActiveModel::Model

    HolidayFormRow = Struct.new(:id, :name, :start_date, :end_date, :price, :persisted?, keyword_init: true)

    attr_accessor :general_rule, :weekends_rule, :school_rule, :walk_in_rule, :pricing_data, :weekend_days,
                  :public_holiday_rows, :selected_room_type_ids, :errors

    def initialize(hotel, room_types)
      @hotel = hotel
      @room_types = room_types
      @errors = {}
    end

    def from_saved_rules
      @general_rule = @hotel.pricing_rules.find_by(rule_type: "general")
      @weekends_rule = @hotel.pricing_rules.find_by(rule_type: "weekends")
      @school_rule = @hotel.pricing_rules.find_by(rule_type: "school_holiday")
      @walk_in_rule = @hotel.pricing_rules.find_by(rule_type: "walk_in")

      @pricing_data = {
        gp_price: @general_rule&.price,
        gp_start_date: @general_rule&.start_date,
        gp_end_date: @general_rule&.end_date,
        wk_price: @weekends_rule&.price,
        wk_start_date: @weekends_rule&.start_date,
        wk_end_date: @weekends_rule&.end_date,
        sc_price: @school_rule&.price,
        sc_start_date: @school_rule&.start_date,
        sc_end_date: @school_rule&.end_date,
        wi_price: @walk_in_rule&.price,
        wi_start_date: @walk_in_rule&.start_date,
        wi_end_date: @walk_in_rule&.end_date
      }

      @weekend_days = @weekends_rule&.weekdays.presence || [ 5, 6, 0 ]
      @public_holiday_rows = @hotel.pricing_rules.public_holidays.order(:start_date, :name).map { |rule| row_from_record(rule) }
      @public_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @public_holiday_rows.empty?
      @selected_room_type_ids = @room_types.map(&:id)
      self
    end

    def from_params(params)
      @general_rule = nil
      @weekends_rule = nil
      @school_rule = nil
      @walk_in_rule = nil

      @pricing_data = {
        gp_price: params[:gp_price],
        gp_start_date: params[:gp_start_date],
        gp_end_date: params[:gp_end_date],
        wk_price: params[:wk_price],
        wk_start_date: params[:wk_start_date],
        wk_end_date: params[:wk_end_date],
        sc_price: params[:sc_price],
        sc_start_date: params[:sc_start_date],
        sc_end_date: params[:sc_end_date],
        wi_price: params[:wi_price],
        wi_start_date: params[:wi_start_date],
        wi_end_date: params[:wi_end_date]
      }

      @weekend_days = Array(params[:weekend_days]).reject(&:blank?).map(&:to_i)
      @weekend_days = [ 5, 6, 0 ] if @weekend_days.empty?

      @selected_room_type_ids = Array(params[:room_type_ids]).reject(&:blank?).map(&:to_i)
      @selected_room_type_ids = @room_types.map(&:id) if @selected_room_type_ids.empty?

      @public_holiday_rows = Array(params[:public_holidays]).map { |row| row_from_hash(row) }
      @public_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @public_holiday_rows.empty?
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
