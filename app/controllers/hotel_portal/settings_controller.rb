# frozen_string_literal: true

module HotelPortal
  class SettingsController < HotelPortal::BaseController
    SETTINGS_TABS = %w[general tax ai notifications banking einvoice].freeze

    before_action :set_account
    before_action :set_hotel
    before_action :authorize_settings_access!, only: [ :index, :edit ]

    def index
      @presenter = settings_presenter
      @account.build_banking_detail unless @account.banking_detail
      append_settings_tab_breadcrumb
    end

    def edit
      @property_policy = settings_policy
    end

    def update
      if notification_update_request?
        update_notification_settings
      elsif settings_update_request?
        update_settings
      elsif params[:payment_setting].present?
        redirect_to hotel_settings_path(@hotel, tab: active_settings_tab), alert: "Payment gateway credentials are managed by superadmin."
      else
        update_banking_details
      end
    end

    private

    def authorize_settings_access!
      has_profile_perm = current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
      has_account_perm = current_user.has_permission?("manage_account")

      raise Pundit::NotAuthorizedError unless has_profile_perm || has_account_perm
    end

    def set_account
      @account = current_user.account
    end

    def set_hotel
      @hotel = current_hotel
    end

    def update_settings
      authorize_settings_update!

      form = HotelPortal::GeneralSettingsForm.new(@hotel, params)

      if form.save
        tab = params[:form_id].to_s == "ai_configuration" ? "ai" : settings_tab_for_form
        redirect_to hotel_settings_path(@hotel, tab: tab), notice: "Settings updated successfully."
      else
        @presenter = settings_presenter
        @account.build_banking_detail unless @account.banking_detail
        append_settings_tab_breadcrumb
        render :index, status: :unprocessable_entity
      end
    end

    def update_banking_details
      authorize_banking_details_update!

      form = HotelPortal::BankingDetailsForm.new(@account, params)

      if form.save
        redirect_to hotel_settings_path(@hotel, tab: "banking"), notice: "Settings updated successfully."
      else
        @presenter = settings_presenter(tab: "banking")
        append_settings_tab_breadcrumb
        render :index, status: :unprocessable_entity
      end
    end

    def update_notification_settings
      authorize_settings_update!

      form = HotelPortal::NotificationSettingsForm.new(@hotel, params)

      if form.save
        redirect_to hotel_settings_path(@hotel, tab: "notifications"), notice: "Settings updated successfully."
      else
        @notification_config = form.config
        @presenter = settings_presenter(tab: "notifications")
        @account.build_banking_detail unless @account.banking_detail
        append_settings_tab_breadcrumb
        render :index, status: :unprocessable_entity
      end
    end

    def authorize_settings_update!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def authorize_banking_details_update!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_account")
    end

    def settings_presenter(tab: active_settings_tab)
      HotelPortal::SettingsPresenter.new(
        hotel: @hotel,
        active_tab: tab,
        current_user: current_user
      )
    end

    def active_settings_tab
      requested_tab = params[:tab].to_s
      return requested_tab if permitted_settings_tabs.include?(requested_tab)

      form_tab = settings_tab_for_form
      return form_tab if permitted_settings_tabs.include?(form_tab)

      "banking"
    end

    def permitted_settings_tabs
      tabs = []
      tabs.concat(SETTINGS_TABS - [ "banking" ]) if current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
      tabs << "banking" if current_user.has_permission?("manage_account")
      tabs
    end

    def append_settings_tab_breadcrumb
      append_breadcrumb({ label: settings_tab_label(@presenter.active_tab), tab_label: true })
    end

    def settings_tab_label(tab)
      {
        "general" => "General",
        "tax" => "Tax",
        "ai" => "AI Concierge",
        "notifications" => "Notifications",
        "banking" => "Banking",
        "einvoice" => "E-Invoice"
      }.fetch(tab, "General")
    end

    def settings_tab_for_form
      case params[:form_id].to_s
      when "hotel_settings" then "general"
      when "tax_settings" then "tax"
      when "ai_configuration" then "ai"
      when "notification_settings" then "notifications"
      when "einvoice_settings" then "einvoice"
      else "general"
      end
    end

    def settings_policy
      current_hotel.property_policy || current_hotel.build_property_policy
    end

    def notification_update_request?
      params[:notification_config].present?
    end

    def settings_update_request?
      params[:hotel].present?
    end
  end
end
