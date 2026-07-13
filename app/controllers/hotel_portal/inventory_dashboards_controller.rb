# frozen_string_literal: true

class HotelPortal::InventoryDashboardsController < HotelPortal::BaseController
  INVENTORY_TABS = %w[calendar advanced channels].freeze
  INVENTORY_SUBTABS = %w[pricing overrides derived_settings availability_rules].freeze

  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy

    @range_mode = params[:days] == "month" ? "month" : "days"

    if @range_mode == "month"
      @month = parsed_month(params[:month]) || (params[:start_date].presence&.to_date || Date.current).beginning_of_month
      @start_date = @month.beginning_of_month
      @end_date = @month.end_of_month
      @days = (@end_date - @start_date).to_i + 1
    else
      @days = (params[:days] || 14).to_i
      @days = 14 unless [ 14, 21 ].include?(@days)
      @start_date = (params[:start_date] || Date.current).to_date
      @end_date = @start_date + (@days - 1).days
    end
    @view_mode = "combined"

    # Handle multiple view currencies
    @hotel_base_currency = current_hotel.default_currency || "MYR"
    requested_currencies = Array(params[:view_currencies]).reject(&:blank?)
    requested_currencies << @hotel_base_currency if requested_currencies.empty?
    @view_currencies = requested_currencies.uniq.select { |c| CurrencyCatalog.valid?(c) }

    # Primary display currency
    @display_currency = normalized_currency(params[:display_currency], fallback: @view_currencies.first)

    # Ensure display currency is in the view list if it was explicitly requested
    @view_currencies = ([ @display_currency ] + @view_currencies).uniq if params[:display_currency].present?

    # Check if exchange rates are set for all view currencies (relative to base)
    @missing_rates = @view_currencies.reject do |currency|
      currency == @hotel_base_currency || ExchangeRate.rate_for(@hotel_base_currency, currency).present?
    end

    @room_types = current_hotel.room_types.order(:id)
    @calendar = build_calendar
    @pricing_form = HotelPortal::PricingForm.new(current_hotel, @room_types).from_saved_rules(params[:room_type_ids])

    load_channels_data

    set_active_tabs
    append_inventory_breadcrumbs
  end

  def occupancy_details
    authorize current_hotel, :update?, policy_class: HotelPolicy

    @date = begin
      params[:date].present? ? params[:date].to_date : Date.current
    rescue StandardError
      Date.current
    end

    @booking_rooms = BookingRoom.joins(:booking)
                                .includes(:room_type, :booking)
                                .where(bookings: { hotel_id: current_hotel.id })
                                .merge(Booking.revenue_generating)
                                .where("bookings.check_in::date <= :date AND bookings.check_out::date > :date", date: @date)
                                .order("booking_rooms.room_number ASC, bookings.guest_name ASC")

    @grouped_booking_rooms = @booking_rooms.group_by(&:room_type).sort_by { |room_type, _| room_type.id }

    render layout: false
  end

  def bulk_save_ari
    authorize current_hotel, :update?, policy_class: HotelPolicy

    begin
      ActiveRecord::Base.transaction do
        Thread.current[:skip_ari_sync] = true

        result = HotelOps::ApplyInventoryDashboardSelection.new(
          hotel: current_hotel,
          selection: selection_update_params.to_h.symbolize_keys,
          user: current_user,
          skip_sync: true
        ).call

        if result[:success]
          # Trigger a single sync job
          if current_hotel.preferred_channel_manager.present?
            s_date = selection_update_params[:start_date]&.to_date
            e_date = selection_update_params[:end_date]&.to_date

            sync_availability = cast_boolean(selection_update_params[:apply_inventory])
            sync_rates = cast_boolean(selection_update_params[:apply_rates])
            sync_restrictions = cast_boolean(selection_update_params[:apply_restrictions])

            # Prepare granular ID-to-window mappings for truly surgical sync
            rt_ids = selection_update_params[:room_type_ids]&.map(&:to_i) || []
            rp_ids = selection_update_params[:rate_plan_ids]&.map(&:to_i) || []

            room_type_ids = {}
            rt_ids.each { |id| room_type_ids[id.to_s] = { "min" => s_date.to_s, "max" => e_date.to_s } }

            rate_plan_ids = {}
            rp_ids.each { |id| rate_plan_ids[id.to_s] = { "min" => s_date.to_s, "max" => e_date.to_s } }

            # Map modified fields to all involved rate plans for this single selection
            modified_fields = Array(selection_update_params[:modified_fields]).reject(&:blank?)
            rate_plan_fields = {}
            rp_ids.each { |id| rate_plan_fields[id.to_s] = modified_fields }

            ChannelManagers::SyncJob.perform_later(
              current_hotel.id,
              s_date,
              e_date,
              sync_availability: sync_availability,
              sync_rates: sync_rates,
              sync_restrictions: sync_restrictions,
              room_type_ids: room_type_ids,
              rate_plan_ids: rate_plan_ids,
              rate_plan_fields: rate_plan_fields
            ) if s_date && e_date
          end

          redirect_to hotel_inventory_index_path(current_hotel, redirect_query_params), notice: "Calendar updated successfully."
        else
          redirect_to hotel_inventory_index_path(current_hotel, redirect_query_params), alert: "Error saving changes: #{result[:error]}"
        end
      end
    ensure
      Thread.current[:skip_ari_sync] = nil
    end
  end

  def batch_save_ari
    authorize current_hotel, :update?, policy_class: HotelPolicy

    # We permit the array of objects coming from the staged frontend state
    staged_updates = params.require(:updates).map do |u|
      u.permit(
        :start_date, :end_date, :apply_inventory, :apply_rates, :apply_restrictions,
        :quantity, :status, :price, :currency, :min_stay, :max_stay,
        :closed_to_arrival, :closed_to_departure, :stop_sell, :mode,
        :base_occupancy, :extra_pax_charge, :single_supplement,
        :channel_id, :channel_rate_plan_id,
        room_type_ids: [], rate_plan_ids: [], modified_fields: []
      ).to_h.symbolize_keys
    end

    result = HotelOps::ProcessBatchUpdates.new(
      hotel: current_hotel,
      updates: staged_updates,
      user: current_user
    ).call

    if result[:success]
      flash[:notice] = result[:message]
      render json: { success: true, message: result[:message] }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
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
      school_holidays: pricing_params[:school_holidays],
      wi_price: pricing_params[:wi_price],
      wi_start_date: pricing_params[:wi_start_date],
      wi_end_date: pricing_params[:wi_end_date],
      cr_price: pricing_params[:cr_price],
      cr_start_date: pricing_params[:cr_start_date],
      cr_end_date: pricing_params[:cr_end_date],
      public_holidays: pricing_params[:public_holidays]
    ).call

    unless sync_result[:success]
      @start_date = Date.current
      @days = (params[:days] || 14).to_i
      @days = 14 unless [ 14, 21 ].include?(@days)
      @end_date = @start_date + (@days - 1).days
      @range_mode = "days"
      @view_mode = "combined"
      @room_types = current_hotel.room_types.order(:id)

      @hotel_base_currency = current_hotel.default_currency || "MYR"
      requested_currencies = Array(params[:view_currencies]).reject(&:blank?)
      requested_currencies << @hotel_base_currency if requested_currencies.empty?
      @view_currencies = requested_currencies.uniq.select { |c| CurrencyCatalog.valid?(c) }
      @display_currency = @view_currencies.first
      @missing_rates = @view_currencies.reject do |currency|
        currency == @hotel_base_currency || ExchangeRate.rate_for(@hotel_base_currency, currency).present?
      end

      @calendar = build_calendar
      @pricing_form = HotelPortal::PricingForm.new(current_hotel, @room_types).from_params(pricing_params)
      @pricing_form.errors = sync_result[:errors] || {}
      load_channels_data
      set_active_tabs
      append_inventory_breadcrumbs
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
      redirect_to hotel_inventory_index_path(current_hotel, start_date: apply_start_date, tab: "advanced", subtab: "pricing", anchor: "top"), notice: "Pricing rules applied successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "pricing", anchor: "top"), alert: "Error applying pricing rules: #{result[:error]}"
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
      redirect_to hotel_inventory_index_path(current_hotel, start_date: availability_params[:start_date], tab: "advanced", subtab: "overrides", anchor: "top"), notice: "Availability override applied successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "overrides", anchor: "top"), alert: "Error applying availability override: #{result[:error]}"
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

    redirect_to hotel_inventory_index_path(current_hotel, start_date: params[:start_date], tab: "advanced", subtab: "pricing", anchor: "top"), notice: "Public holiday removed successfully."
  rescue ActiveRecord::RecordNotFound
    redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "pricing", anchor: "top"), alert: "Public holiday rule not found."
  end

  def destroy_pricing_tier_rule
    authorize current_hotel, :update?, policy_class: HotelPolicy

    rule_type = params[:rule_type].to_s
    unless %w[general weekends school_holiday walk_in corporate_rate ota_rate].include?(rule_type)
      return redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "pricing", anchor: "top"), alert: "Unsupported pricing tier."
    end

    pricing_rule = current_hotel.pricing_rules.find_by(rule_type: rule_type)
    return redirect_to(hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "pricing", anchor: "top"), alert: "Pricing tier not found.") if pricing_rule.blank?

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

    redirect_to hotel_inventory_index_path(current_hotel, start_date: params[:start_date], tab: "advanced", subtab: "pricing", anchor: "top"), notice: "#{rule_type.humanize} pricing removed successfully."
  end

  def update_channel_derived_pricing
    authorize current_hotel, :update?, policy_class: HotelPolicy

    channel_id = params[:channel_id]
    pricing_mode = params[:pricing_mode] || "same"
    pricing_value = params[:pricing_value].presence&.to_d
    room_allocation_mode = params[:room_allocation_mode] || "shared"
    room_allocation_value = params[:room_allocation_value].presence&.to_i

    setting = current_hotel.channel_derived_settings.find_or_initialize_by(channel_id: channel_id)
    setting.pricing_mode = pricing_mode
    setting.pricing_value = pricing_mode == "same" ? nil : pricing_value
    setting.room_allocation_mode = room_allocation_mode
    setting.room_allocation_value = room_allocation_mode == "shared" ? nil : room_allocation_value

    if setting.save
      redirect_to hotel_inventory_index_path(current_hotel, tab: "channels", subtab: "derived_settings"), notice: "Derived pricing settings for channel updated successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel, tab: "channels", subtab: "derived_settings"), alert: "Failed to update channel settings: #{setting.errors.full_messages.to_sentence}"
    end
  end

  def create_channel_availability_rule
    authorize current_hotel, :update?, policy_class: HotelPolicy

    # Translate parameters
    start_date = params[:start_date]
    end_date = params[:end_date].presence
    rule_type = params[:rule_type]
    value = params[:value]
    title = params[:title].presence || "PMS Override"

    # Weekdays list
    days_list = []
    days_list << "mo" if params[:day_mo] == "1"
    days_list << "tu" if params[:day_tu] == "1"
    days_list << "we" if params[:day_we] == "1"
    days_list << "th" if params[:day_th] == "1"
    days_list << "fr" if params[:day_fr] == "1"
    days_list << "sa" if params[:day_sa] == "1"
    days_list << "su" if params[:day_su] == "1"
    days_string = days_list.join(",")

    affected_channels = Array(params[:affected_channels]).reject(&:blank?)
    affected_room_types = Array(params[:affected_room_types]).reject(&:blank?).map(&:to_i)

    rule = current_hotel.channel_availability_rules.build(
      title: title,
      start_date: start_date,
      end_date: end_date,
      rule_type: rule_type,
      value: value,
      days: days_string,
      affected_channels: affected_channels,
      affected_room_types: affected_room_types
    )

    if rule.save
      redirect_to hotel_inventory_index_path(current_hotel, tab: "channels", subtab: "availability_rules"), notice: "Availability rule created and synced successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel, tab: "channels", subtab: "availability_rules"), alert: "Failed to create rule: #{rule.errors.full_messages.to_sentence}"
    end
  end

  def destroy_channel_availability_rule
    authorize current_hotel, :update?, policy_class: HotelPolicy

    rule = current_hotel.channel_availability_rules.find(params[:id])
    if rule.destroy
      redirect_to hotel_inventory_index_path(current_hotel, tab: "channels", subtab: "availability_rules"), notice: "Availability rule deleted and synced successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel, tab: "channels", subtab: "availability_rules"), alert: "Failed to delete rule."
    end
  end

  private

  def build_calendar
    presenter = HotelPortal::InventoryCalendarPresenter.new(
      hotel: current_hotel,
      start_date: @start_date,
      end_date: @end_date,
      display_currency: @display_currency,
      room_type_id: selected_room_type_id,
      rate_plan_id: selected_rate_plan_id
    )
    @last_pricing_applied_at = current_hotel.inventory_audit_logs
      .where(action_type: "rate_update")
      .where("metadata ->> 'source' = ?", "pricing_rules")
      .maximum(:created_at)
    presenter
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
      :wi_price,
      :wi_start_date,
      :wi_end_date,
      :cr_price,
      :cr_start_date,
      :cr_end_date,
      room_type_ids: [],
      weekend_days: [],
      school_holidays: [ :name, :price, :start_date, :end_date ],
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

  def selection_update_params
    params.require(:selection_update).permit(
      :start_date,
      :end_date,
      :apply_inventory,
      :apply_rates,
      :apply_restrictions,
      :quantity,
      :status,
      :price,
      :currency,
      :min_stay,
      :max_stay,
      :closed_to_arrival,
      :closed_to_departure,
      :stop_sell,
      :mode,
      :base_occupancy,
      :extra_pax_charge,
      :single_supplement,
      :channel_id,
      :channel_rate_plan_id,
      room_type_ids: [],
      rate_plan_ids: [],
      view_currencies: [],
      available_room_numbers: []
    )
  end

  def parsed_month(value)
    return nil if value.blank?

    Date.strptime(value.to_s, "%Y-%m").beginning_of_month
  rescue ArgumentError, TypeError
    nil
  end

  def redirect_query_params
    permitted_selection = selection_update_params

    {
      start_date: params[:start_date] || permitted_selection[:start_date],
      days: params[:days],
      month: params[:month],
      view_currencies: params[:view_currencies] || permitted_selection[:view_currencies],
      display_currency: params[:display_currency],
      room_type_id: Array(permitted_selection[:room_type_ids]).reject(&:blank?).first || params[:room_type_id],
      rate_plan_id: Array(permitted_selection[:rate_plan_ids]).reject(&:blank?).first || params[:rate_plan_id],
      tab: params[:tab],
      subtab: params[:subtab]
    }.compact
  end

  def selected_room_type_id
    return nil if params.key?(:room_type_id) && params[:room_type_id].blank?

    params[:room_type_id].presence || Array(params[:room_type_ids]).reject(&:blank?).first
  end

  def selected_rate_plan_id
    params[:rate_plan_id].presence || Array(params[:rate_plan_ids]).reject(&:blank?).first
  end

  def normalized_currency(value, fallback:)
    normalized = CurrencyCatalog.normalize(value, fallback: fallback)
    CurrencyCatalog.valid?(normalized) ? normalized : fallback
  end

  def cast_boolean(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def set_active_tabs
    @active_tab = INVENTORY_TABS.include?(params[:tab]) ? params[:tab] : "calendar"
    default_subtab = if @active_tab == "channels"
      "derived_settings"
    else
      "pricing"
    end
    @active_subtab = INVENTORY_SUBTABS.include?(params[:subtab]) ? params[:subtab] : default_subtab
  end

  def append_inventory_breadcrumbs
    append_breadcrumb({ label: inventory_tab_label, tab_label: true })
    append_breadcrumb({
      label: inventory_subtab_label,
      subtab_label: true,
      hidden: !@active_tab.in?([ "advanced", "channels" ])
    })
  end

  def inventory_tab_label
    case @active_tab
    when "advanced" then "Advanced Pricing"
    when "channels" then "Channels & OTAs"
    else "Rates & Availability"
    end
  end

  def inventory_subtab_label
    case @active_subtab
    when "overrides" then "Availability Overrides"
    when "pricing" then "Pricing Rules"
    when "derived_settings" then "Derived Pricing & Allocations"
    when "availability_rules" then "Availability Rules"
    end
  end

  def load_channels_data
    if current_hotel.preferred_channel_manager == "channex"
      adapter = ChannelManagers::SyncOrchestrator.adapter_for(current_hotel)
      force = ActiveModel::Type::Boolean.new.cast(params[:force_refresh])
      @channels = adapter.connected_channels(force_refresh: force)
      @derived_settings_by_channel_id = current_hotel.channel_derived_settings.index_by(&:channel_id)
      @availability_rules = current_hotel.channel_availability_rules.order(created_at: :desc)
    else
      @channels = []
      @derived_settings_by_channel_id = {}
      @availability_rules = []
    end
  end
end
