# frozen_string_literal: true

class HotelPortal::InventoryDashboardsController < HotelPortal::BaseController
  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy

    @start_date = (params[:start_date] || Date.today).to_date
    @end_date = @start_date + 13.days
    @view_mode = "combined"

    # Handle multiple view currencies
    @hotel_base_currency = current_hotel.default_currency || "MYR"
    requested_currencies = Array(params[:view_currencies]).reject(&:blank?)
    requested_currencies << @hotel_base_currency if requested_currencies.empty?
    @view_currencies = requested_currencies.uniq.select { |c| CurrencyCatalog.valid?(c) }

    # Primary display currency is the first one in the list
    @display_currency = @view_currencies.first

    # Check if exchange rates are set for all view currencies (relative to base)
    @missing_rates = @view_currencies.reject do |currency|
      currency == @hotel_base_currency || ExchangeRate.rate_for(@hotel_base_currency, currency).present?
    end

    @room_types = current_hotel.room_types.order(:id)
    @partners = current_hotel.partners.ordered
    @calendar = build_calendar
    @pricing_form = HotelPortal::PricingForm.new(current_hotel, @room_types).from_saved_rules
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
        :closed_to_arrival, :closed_to_departure, :stop_sell,
        room_type_ids: [], rate_plan_ids: [], modified_fields: []
      ).to_h.symbolize_keys
    end

    errors = []
    min_date = nil
    max_date = nil
    sync_availability = false
    sync_rates = false
    sync_restrictions = false
    room_type_windows = {}
    rate_plan_windows = {}
    rate_plan_fields = {}

    begin
      ActiveRecord::Base.transaction do
        Thread.current[:skip_ari_sync] = true

        staged_updates.each do |selection|
          # Track the overall date range and sync types for a single final sync
          s_date = selection[:start_date]&.to_date
          e_date = selection[:end_date]&.to_date

          # Guard against missing dates
          next unless s_date && e_date

          min_date = [ min_date, s_date ].compact.min
          max_date = [ max_date, e_date ].compact.max

          sync_availability ||= cast_boolean(selection[:apply_inventory])
          sync_rates ||= cast_boolean(selection[:apply_rates])
          sync_restrictions ||= cast_boolean(selection[:apply_restrictions])

          Array(selection[:room_type_ids]).each do |id|
            win = room_type_windows[id.to_s] || { "min" => s_date.to_s, "max" => e_date.to_s }
            win["min"] = [ win["min"].to_date, s_date ].min.to_s
            win["max"] = [ win["max"].to_date, e_date ].max.to_s
            room_type_windows[id.to_s] = win
          end

          Array(selection[:rate_plan_ids]).each do |id|
            win = rate_plan_windows[id.to_s] || { "min" => s_date.to_s, "max" => e_date.to_s }
            win["min"] = [ win["min"].to_date, s_date ].min.to_s
            win["max"] = [ win["max"].to_date, e_date ].max.to_s
            rate_plan_windows[id.to_s] = win

            # Track which fields were modified for this rate plan
            rate_plan_fields[id.to_s] ||= Set.new
            rate_plan_fields[id.to_s].merge(Array(selection[:modified_fields]))
          end

          result = HotelOps::ApplyInventoryDashboardSelection.new(
            hotel: current_hotel,
            selection: selection,
            user: current_user,
            skip_sync: true
          ).call

          unless result[:success]
            errors << result[:error]
            raise ActiveRecord::Rollback
          end
        end

        # Trigger a single sync job covering the entire updated range with granular ID windows
        if current_hotel.preferred_channel_manager.present? && min_date && max_date
          ChannelManagers::SyncJob.perform_later(
            current_hotel.id,
            min_date,
            max_date,
            sync_availability: sync_availability,
            sync_rates: sync_rates,
            sync_restrictions: sync_restrictions,
            room_type_ids: room_type_windows,
            rate_plan_ids: rate_plan_windows,
            rate_plan_fields: rate_plan_fields.transform_values(&:to_a)
          )
        end
      end
    rescue => e
      Rails.logger.error "Batch ARI Sync Failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      errors << "Unexpected error: #{e.message}"
    ensure
      Thread.current[:skip_ari_sync] = nil
    end

    if errors.empty?
      render json: { success: true, message: "All changes synced successfully." }
    else
      render json: { success: false, error: errors.join(", ") }, status: :unprocessable_entity
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
      sc_price: pricing_params[:sc_price],
      sc_start_date: pricing_params[:sc_start_date],
      sc_end_date: pricing_params[:sc_end_date],
      wi_price: pricing_params[:wi_price],
      wi_start_date: pricing_params[:wi_start_date],
      wi_end_date: pricing_params[:wi_end_date],
      cr_price: pricing_params[:cr_price],
      cr_start_date: pricing_params[:cr_start_date],
      cr_end_date: pricing_params[:cr_end_date],
      ota_price: pricing_params[:ota_price],
      ota_start_date: pricing_params[:ota_start_date],
      ota_end_date: pricing_params[:ota_end_date],
      public_holidays: pricing_params[:public_holidays]
    ).call

    unless sync_result[:success]
      @start_date = Date.today
      @end_date = @start_date + 13.days
      @view_mode = "combined"
      @room_types = current_hotel.room_types.order(:id)
      @partners = current_hotel.partners.ordered

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
    unless %w[general weekends school_holiday walk_in corporate_rate ota_rate].include?(rule_type)
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
      :ota_price,
      :ota_start_date,
      :ota_end_date,
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
      room_type_ids: [],
      rate_plan_ids: [],
      view_currencies: [],
      available_room_numbers: []
    )
  end

  def redirect_query_params
    permitted_selection = selection_update_params

    {
      start_date: params[:start_date] || permitted_selection[:start_date],
      view_currencies: params[:view_currencies] || permitted_selection[:view_currencies],
      room_type_id: Array(permitted_selection[:room_type_ids]).reject(&:blank?).first || params[:room_type_id],
      rate_plan_id: Array(permitted_selection[:rate_plan_ids]).reject(&:blank?).first || params[:rate_plan_id]
    }
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
end
