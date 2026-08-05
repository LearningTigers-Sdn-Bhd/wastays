# frozen_string_literal: true

module HotelPortal
  # Room Revenue: ROOM's tax rules, the blast-radius control that governs them,
  # and the four stay-event policies.
  #
  # The code being edited is always ROOM — resolved, never taken from params.
  # The four stay-event codes inherit its rules via
  # TransactionCodes::Resolver#tax_rule_source_for, so there is nothing else here
  # to edit and no id to pass.
  class RoomRevenueController < SettingsBaseController
    TABS = %w[tax_rules reservation_policies].freeze

    before_action :authorize!
    before_action :ensure_defaults
    before_action :set_room_revenue_code

    def show
      @presenter = presenter
      append_room_revenue_tab_breadcrumb
    end

    # Step one of the hotel-wide change: show what it would do before doing it.
    # When nothing material is at stake the save happens straight away.
    def preview_tax_rules
      @room_revenue_code.assign_attributes(taxable_attributes)

      @tax_rule_change = ::TransactionCodes::HotelTaxRuleChange.preview(
        transaction_code: @room_revenue_code,
        proposed_keys: tax_rule_keys_param
      )
      return update_tax_rules unless @tax_rule_change.changed? && review_required?(@tax_rule_change)

      render :confirm_hotel_tax_rules, formats: :html
    rescue ArgumentError => e
      render_tax_rule_error(e.message)
    end

    def update_tax_rules
      @room_revenue_code.assign_attributes(taxable_attributes)

      unless tax_rules_changed?
        return save_without_hotel_wide_confirmation
      end

      unless confirmed?
        return render_tax_rule_error("Review and confirm hotel-wide tax inclusion changes before applying them.") if review_required_for_current_change?

        return save_without_hotel_wide_confirmation
      end

      result = ::TransactionCodes::ApplyHotelTaxRuleChange.call(
        transaction_code: @room_revenue_code,
        actor: current_user,
        attributes: taxable_attributes,
        proposed_keys: tax_rule_keys_param,
        reason: params[:reason],
        freshness_token: params[:freshness_token]
      )
      return render_tax_rule_error(result.error) unless result.success?

      redirect_to hotel_room_revenue_path(current_hotel), notice: "Room revenue tax rules updated."
    end

    def update_configuration
      configuration = current_hotel.transaction_configuration
      configuration.assign_attributes(transaction_configuration_params)

      if configuration.save
        refresh_open_folio_forecasts_if_needed
        redirect_to hotel_room_revenue_path(current_hotel), notice: "Room revenue configuration updated."
      else
        @presenter = presenter
        @configuration_errors = configuration.errors.full_messages
        append_room_revenue_tab_breadcrumb
        render :show, status: :unprocessable_entity
      end
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def ensure_defaults
      ReservationPolicies::EnsureDefaults.call(current_hotel)
    end

    def set_room_revenue_code
      @room_revenue_code = ::TransactionCodes::Resolver.for(current_hotel).room_revenue
      raise ActiveRecord::RecordNotFound, "no ROOM transaction code for hotel #{current_hotel.id}" if @room_revenue_code.blank?
    end

    def presenter(tab: active_tab)
      HotelPortal::RoomRevenuePresenter.new(hotel: current_hotel, active_tab: tab)
    end

    def active_tab
      TABS.include?(params[:tab].to_s) ? params[:tab].to_s : "tax_rules"
    end

    # ROOM is taxable exactly when it carries rules; there is no separate switch
    # to get out of step with the selection.
    def taxable_attributes
      { is_taxable: tax_rule_keys_param.any? }
    end

    def tax_rule_keys_param
      @tax_rule_keys_param ||= Array(params.dig(:transaction_code, :tax_rule_keys)).reject(&:blank?).map(&:to_s).uniq
    end

    def tax_rules_changed?
      @room_revenue_code.transaction_code_taxes.reload.map(&:tax_rule_key).sort != tax_rule_keys_param.sort
    end

    def confirmed?
      ActiveModel::Type::Boolean.new.cast(params[:confirm_hotel_tax_rules])
    end

    def review_required?(tax_rule_change)
      tax_rule_change.forecast_count.to_i.positive?
    end

    def review_required_for_current_change?
      @tax_rule_change = ::TransactionCodes::HotelTaxRuleChange.preview(
        transaction_code: @room_revenue_code,
        proposed_keys: tax_rule_keys_param
      )
      review_required?(@tax_rule_change)
    rescue ArgumentError
      true
    end

    def save_without_hotel_wide_confirmation
      if @room_revenue_code.save
        assign_tax_rules
        redirect_to hotel_room_revenue_path(current_hotel), notice: "Room revenue tax rules updated."
      else
        render_tax_rule_error(@room_revenue_code.errors.full_messages.to_sentence)
      end
    rescue ArgumentError => e
      render_tax_rule_error(e.message)
    end

    def assign_tax_rules
      keys = tax_rule_keys_param
      invalid = keys - available_tax_rule_keys
      raise ArgumentError, "A selected tax rule is unavailable for this hotel." if invalid.any?

      @room_revenue_code.transaction_code_taxes.destroy_all
      keys.each do |key|
        if key.start_with?("primary:")
          @room_revenue_code.transaction_code_taxes.create!(primary_tax_key: key.delete_prefix("primary:"))
        else
          tax = current_hotel.hotel_taxes.find(key.delete_prefix("hotel_tax:"))
          @room_revenue_code.transaction_code_taxes.create!(hotel_tax: tax)
        end
      end
    end

    def available_tax_rule_keys
      @available_tax_rule_keys ||= TransactionCodeTax::PRIMARY_TAX_KEYS.map { |key| "primary:#{key}" } +
        current_hotel.hotel_taxes.pluck(:id).map { |id| "hotel_tax:#{id}" }
    end

    def render_tax_rule_error(message)
      @room_revenue_code.restore_attributes
      @presenter = presenter(tab: "tax_rules")
      @tax_rule_errors = [ message ]
      @proposed_tax_rule_keys = tax_rule_keys_param
      append_room_revenue_tab_breadcrumb
      render :show, status: :unprocessable_entity
    end

    def transaction_configuration_params
      params.require(:hotel_transaction_configuration).permit(:room_revenue_tax_rule_application)
    end

    def refresh_open_folio_forecasts_if_needed
      return unless current_hotel.transaction_configuration.open_folio_forecasts?

      ::Folios::Forecasts::RefreshOpenForecastsFromRoomRevenueRules.call(hotel: current_hotel, actor: current_user)
    end

    def append_room_revenue_tab_breadcrumb
      append_breadcrumb({ label: tab_label(@presenter.active_tab), tab_label: true, tabs_id: "room-revenue-tabs" })
    end

    def tab_label(tab)
      @presenter.tabs.find { |item| item[:name] == tab }&.fetch(:label) || "Tax rules"
    end
  end
end
