class HotelPortal::InventoryDashboardsController < HotelPortal::BaseController
  HolidayFormRow = Struct.new(:id, :name, :start_date, :end_date, :price, :persisted?, keyword_init: true)

  WEEKDAY_OPTIONS = [
    [ "Mon", 1 ],
    [ "Tue", 2 ],
    [ "Wed", 3 ],
    [ "Thu", 4 ],
    [ "Fri", 5 ],
    [ "Sat", 6 ],
    [ "Sun", 0 ]
  ].freeze

  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy

    @start_date = (params[:start_date] || Date.today).to_date
    @end_date = @start_date + 13.days # Show 14 days by default
    load_dashboard_data
    load_pricing_form_from_saved_rules
  end

  def apply_pricing_rules
    authorize current_hotel, :update?, policy_class: HotelPolicy

    sync_result = HotelOps::SyncPricingRules.new(
      hotel: current_hotel,
      gp_price: pricing_params[:gp_price],
      gp_start_date: pricing_params[:gp_start_date],
      gp_end_date: pricing_params[:gp_end_date],
      wk_price: pricing_params[:wk_price],
      wk_start_date: pricing_params[:wk_start_date],
      wk_end_date: pricing_params[:wk_end_date],
      weekend_days: pricing_params[:weekend_days],
      sc_price: pricing_params[:sc_price],
      sc_start_date: pricing_params[:sc_start_date],
      sc_end_date: pricing_params[:sc_end_date],
      public_holidays: pricing_params[:public_holidays]
    ).call

    unless sync_result[:success]
      @start_date = Date.today
      @end_date = @start_date + 13.days
      load_dashboard_data
      load_pricing_form_from_params(pricing_params)
      @pricing_errors = sync_result[:errors] || {}
      flash.now[:alert] = sync_result[:error] || "Error saving pricing rules."
      return render :index, status: :unprocessable_entity
    end

    apply_start_date = sync_result[:apply_start_date]
    apply_end_date = sync_result[:apply_end_date]

    result = HotelOps::ApplyPricingRules.new(
      hotel: current_hotel,
      room_type_ids: pricing_params[:room_type_ids],
      start_date: apply_start_date,
      end_date: apply_end_date,
      user: current_user
    ).call

    if result[:success]
      redirect_to hotel_inventory_index_path(current_hotel, start_date: apply_start_date), notice: "Pricing rules applied successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel), alert: "Error applying pricing rules: #{result[:error]}"
    end
  end

  def apply_availability_override
    authorize current_hotel, :update?, policy_class: HotelPolicy

    result = HotelOps::BulkUpdateRatesAndInventory.new(
      hotel: current_hotel,
      room_type_ids: availability_params[:room_type_ids],
      start_date: availability_params[:start_date],
      end_date: availability_params[:end_date],
      quantity: availability_params[:quantity],
      status: availability_params[:status],
      room_numbers: availability_params[:room_numbers],
      user: current_user
    ).call

    if result[:success]
      redirect_to hotel_inventory_index_path(current_hotel, start_date: availability_params[:start_date]), notice: "Availability override applied successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel), alert: "Error applying availability override: #{result[:error]}"
    end
  end

  def destroy_public_holiday_rule
    authorize current_hotel, :update?, policy_class: HotelPolicy

    holiday_rule = current_hotel.pricing_rules.public_holidays.find(params[:id])
    affected_start_date = holiday_rule.start_date
    affected_end_date = holiday_rule.end_date
    holiday_rule.destroy!

    HotelOps::ApplyPricingRules.new(
      hotel: current_hotel,
      room_type_ids: current_hotel.room_types.pluck(:id),
      start_date: affected_start_date,
      end_date: affected_end_date,
      user: current_user
    ).call

    redirect_to hotel_inventory_index_path(current_hotel, start_date: params[:start_date]), notice: "Public holiday removed successfully."
  rescue ActiveRecord::RecordNotFound
    redirect_to hotel_inventory_index_path(current_hotel), alert: "Public holiday rule not found."
  end

  def destroy_pricing_tier_rule
    authorize current_hotel, :update?, policy_class: HotelPolicy

    rule_type = params[:rule_type].to_s
    unless %w[general weekends school_holiday].include?(rule_type)
      return redirect_to hotel_inventory_index_path(current_hotel), alert: "Unsupported pricing tier."
    end

    pricing_rule = current_hotel.pricing_rules.find_by(rule_type: rule_type)
    return redirect_to(hotel_inventory_index_path(current_hotel), alert: "Pricing tier not found.") if pricing_rule.blank?

    affected_start_date = pricing_rule.start_date
    affected_end_date = pricing_rule.end_date
    pricing_rule.destroy!

    HotelOps::ApplyPricingRules.new(
      hotel: current_hotel,
      room_type_ids: current_hotel.room_types.pluck(:id),
      start_date: affected_start_date,
      end_date: affected_end_date,
      user: current_user
    ).call

    redirect_to hotel_inventory_index_path(current_hotel, start_date: params[:start_date]), notice: "#{rule_type.humanize} pricing removed successfully."
  end

  private

  def load_dashboard_data
    @room_types = current_hotel.room_types.includes(:room_inventories, :room_rates)
    @inventory_matrix = {}
    @rates_matrix = {}

    @room_types.each do |rt|
      @inventory_matrix[rt.id] = rt.room_inventories.where(date: @start_date..@end_date).index_by(&:date)
      @rates_matrix[rt.id] = rt.room_rates.where(date: @start_date..@end_date).index_by(&:date)
    end

    @last_pricing_applied_at = current_hotel.inventory_audit_logs
      .where(action_type: "rate_update")
      .where("metadata ->> 'source' = ?", "pricing_rules")
      .maximum(:created_at)
  end

  def load_pricing_form_from_saved_rules
    general_rule = current_hotel.pricing_rules.find_by(rule_type: "general")
    weekends_rule = current_hotel.pricing_rules.find_by(rule_type: "weekends")
    school_rule = current_hotel.pricing_rules.find_by(rule_type: "school_holiday")
    public_rows = current_hotel.pricing_rules.public_holidays.order(:start_date, :name).map { |rule| row_from_record(rule) }

    @general_rule = general_rule
    @weekends_rule = weekends_rule
    @school_rule = school_rule
    @pricing_form = {
      gp_price: general_rule&.price,
      gp_start_date: general_rule&.start_date,
      gp_end_date: general_rule&.end_date,
      wk_price: weekends_rule&.price,
      wk_start_date: weekends_rule&.start_date,
      wk_end_date: weekends_rule&.end_date,
      sc_price: school_rule&.price,
      sc_start_date: school_rule&.start_date,
      sc_end_date: school_rule&.end_date
    }
    @weekend_days = weekends_rule&.weekdays.presence || [ 5, 6, 0 ]
    @public_holiday_rows = public_rows.presence || [ HolidayFormRow.new(persisted?: false) ]
    @selected_room_type_ids = @room_types.map(&:id)
    @pricing_errors = {}
  end

  def load_pricing_form_from_params(params)
    @general_rule = nil
    @weekends_rule = nil
    @school_rule = nil
    @pricing_form = {
      gp_price: params[:gp_price],
      gp_start_date: params[:gp_start_date],
      gp_end_date: params[:gp_end_date],
      wk_price: params[:wk_price],
      wk_start_date: params[:wk_start_date],
      wk_end_date: params[:wk_end_date],
      sc_price: params[:sc_price],
      sc_start_date: params[:sc_start_date],
      sc_end_date: params[:sc_end_date]
    }
    @weekend_days = Array(params[:weekend_days]).reject(&:blank?).map(&:to_i)
    @weekend_days = [ 5, 6, 0 ] if @weekend_days.empty?
    @selected_room_type_ids = Array(params[:room_type_ids]).reject(&:blank?).map(&:to_i)
    @selected_room_type_ids = @room_types.map(&:id) if @selected_room_type_ids.empty?
    @public_holiday_rows = Array(params[:public_holidays]).map { |row| row_from_hash(row) }
    @public_holiday_rows = [ HolidayFormRow.new(persisted?: false) ] if @public_holiday_rows.empty?
  end

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

  def pricing_params
    params.require(:pricing_rule).permit(
      :gp_price,
      :gp_start_date,
      :gp_end_date,
      :wk_price,
      :wk_start_date,
      :wk_end_date,
      :sc_price,
      :sc_start_date,
      :sc_end_date,
      room_type_ids: [],
      weekend_days: [],
      public_holidays: [ :name, :price, :start_date, :end_date ]
    )
  end

  def availability_params
    params.require(:availability_override).permit(
      :start_date,
      :end_date,
      :quantity,
      :status,
      room_type_ids: [],
      room_numbers: []
    )
  end
end
