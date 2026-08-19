# frozen_string_literal: true

module HotelPortal
  class SettingsController < HotelPortal::SettingsBaseController
    SETTINGS_PAGES = %w[general boat ai notifications banking e_invoice].freeze

    before_action :set_account
    before_action :set_hotel
    before_action :authorize_settings_access!, only: [ :show, :index ]

    def show
      redirect_to(params[:tab].present? ? legacy_tab_destination : settings_page_path(active_settings_page), status: :moved_permanently)
    end

    def index
      return redirect_to(settings_page_path(active_settings_page)) if params[:settings_page] != active_settings_page

      prepare_settings_page
    end

    def update
      if e_invoice_update_request?
        update_e_invoice_settings
      elsif notification_update_request?
        update_notification_settings
      elsif settings_update_request?
        update_settings
      elsif params[:payment_setting].present?
        redirect_to settings_page_path(active_settings_page), alert: "Payment gateway credentials are managed by superadmin."
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
        redirect_to settings_page_path(settings_page_for_form), notice: "Settings updated successfully."
      else
        prepare_settings_page
        render :index, status: :unprocessable_entity
      end
    end

    def update_banking_details
      authorize_banking_details_update!

      form = HotelPortal::BankingDetailsForm.new(@account, params)

      if form.save
        redirect_to hotel_banking_details_settings_path(@hotel), notice: "Settings updated successfully."
      else
        @presenter = settings_presenter(page: "banking")
        @account.build_banking_detail unless @account.banking_detail
        render :index, status: :unprocessable_entity
      end
    end

    def update_e_invoice_settings
      authorize_settings_update!

      form = HotelPortal::EInvoiceSettingsForm.new(@hotel, params)

      if form.save
        redirect_to hotel_e_invoice_settings_path(@hotel), notice: "Settings updated successfully."
      else
        @e_invoice_setting = form.setting
        @presenter = settings_presenter(page: "e_invoice")
        render :index, status: :unprocessable_entity
      end
    end

    def update_notification_settings
      authorize_settings_update!

      form = HotelPortal::NotificationSettingsForm.new(@hotel, params)

      if form.save
        redirect_to hotel_notification_settings_path(@hotel), notice: "Settings updated successfully."
      else
        @notification_config = form.config
        @presenter = settings_presenter(page: "notifications")
        render :index, status: :unprocessable_entity
      end
    end

    def authorize_settings_update!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def authorize_banking_details_update!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_account")
    end

    def active_settings_page
      requested_page = params[:settings_page].to_s
      return requested_page if permitted_settings_pages.include?(requested_page)

      form_page = settings_page_for_form
      return form_page if permitted_settings_pages.include?(form_page)

      "banking"
    end

    def prepare_settings_page
      @presenter = settings_presenter
      @account.build_banking_detail unless @account.banking_detail
      @e_invoice_setting = @hotel.e_invoice_setting || @hotel.build_e_invoice_setting
    end

    def settings_presenter(page: active_settings_page)
      HotelPortal::SettingsPresenter.new(
        hotel: @hotel,
        active_page: page,
        current_user: current_user
      )
    end

    def permitted_settings_pages
      pages = []
      pages.concat(SETTINGS_PAGES - [ "banking" ]) if current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
      pages << "banking" if current_user.has_permission?("manage_account")
      pages
    end

    def settings_page_for_form
      case params[:form_id].to_s
      when "hotel_settings" then "general"
      when "boat_settings" then "boat"
      when "ai_configuration" then "ai"
      when "notification_settings" then "notifications"
      when "e_invoice_settings" then "e_invoice"
      else "general"
      end
    end

    def settings_page_path(page)
      case page
      when "boat" then hotel_boat_settings_path(@hotel)
      when "ai" then hotel_ai_concierge_settings_path(@hotel)
      when "notifications" then hotel_notification_settings_path(@hotel)
      when "banking" then hotel_banking_details_settings_path(@hotel)
      when "e_invoice" then hotel_e_invoice_settings_path(@hotel)
      else hotel_general_settings_path(@hotel)
      end
    end

    def legacy_tab_destination
      case params[:tab]
      when "hotel_details" then edit_hotel_profile_path(@hotel)
      when "taxes_fees" then hotel_taxes_fees_path(@hotel)
      when "rates" then hotel_room_types_path(@hotel)
      else settings_page_path(params[:tab])
      end
    end

    def notification_update_request?
      params[:notification_config].present?
    end

    def e_invoice_update_request?
      params[:e_invoice_setting].present?
    end

    def settings_update_request?
      params[:hotel].present?
    end
  end
end
