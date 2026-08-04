# frozen_string_literal: true

module HotelPortal
  class TaxesFeesController < HotelPortal::SettingsBaseController
    include SheetActionCompletion

    SYSTEM_TAXES = %w[sst tourism_tax].freeze

    before_action :set_hotel
    before_action :authorize!
    before_action :set_system_tax, only: %i[edit_system update_system]

    def show
      prepare_taxes_fees_page
    end

    def update
      form = HotelPortal::TaxSettingsForm.new(@hotel, params)

      if form.save
        redirect_to registry_path, notice: "Tax settings updated successfully."
      else
        prepare_taxes_fees_page
        render :show, status: :unprocessable_entity
      end
    end

    def edit_system
      render layout: false
    end

    def update_system
      form = HotelPortal::TaxSettingsForm.new(@hotel, scoped_system_tax_params)

      if form.save
        if params[:registry_status].present?
          redirect_to registry_path, notice: "#{system_tax_name} updated."
        else
          complete_sheet_action(
            destination: registry_path,
            notice: "#{system_tax_name} updated.",
            frame: turbo_frame_request_id.presence || "settings_action_sheet"
          )
        end
      else
        render :edit_system, formats: :html, layout: false, status: :unprocessable_entity
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def prepare_taxes_fees_page
      @presenter = HotelPortal::TaxesFeesPresenter.new(
        hotel: @hotel,
        current_user: current_user,
        active_tab: params[:tab]
      )
    end

    def set_system_tax
      @system_tax = params[:tax_key].to_s
      raise ActiveRecord::RecordNotFound unless SYSTEM_TAXES.include?(@system_tax)
    end

    def scoped_system_tax_params
      allowed = @system_tax == "sst" ? [ :sst_enabled ] : %i[tourism_tax_enabled tourism_tax_amount]
      ActionController::Parameters.new(hotel: params.require(:hotel).permit(*allowed).to_h)
    end

    def system_tax_name
      @system_tax == "sst" ? "Service Tax (SST)" : "Tourism Tax (TTx)"
    end

    def registry_path
      hotel_taxes_fees_path(@hotel, tab: "registry")
    end
  end
end
