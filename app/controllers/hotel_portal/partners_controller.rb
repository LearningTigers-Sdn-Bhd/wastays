# frozen_string_literal: true

module HotelPortal
  class PartnersController < HotelPortal::BaseController
    before_action :authorize_hotel!
    before_action :set_partner, only: [ :update, :destroy ]

    def create
      partner = current_hotel.partners.new(partner_params)

      if partner.save
        redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "partners"), notice: "Partner created successfully."
      else
        redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "partners"), alert: partner.errors.full_messages.to_sentence
      end
    end

    def update
      if @partner.update(partner_params)
        redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "partners"), notice: "Partner updated successfully."
      else
        redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "partners"), alert: @partner.errors.full_messages.to_sentence
      end
    end

    def destroy
      @partner.destroy!
      redirect_to hotel_inventory_index_path(current_hotel, tab: "advanced", subtab: "partners"), notice: "Partner deleted successfully."
    rescue ActiveRecord::InvalidForeignKey
      redirect_back fallback_location: hotel_inventory_index_path(current_hotel), alert: "Cannot delete partner because they have associated bookings or quotes."
    rescue StandardError => e
      redirect_back fallback_location: hotel_inventory_index_path(current_hotel), alert: "Failed to delete partner: #{e.message}"
    end

    private

    def authorize_hotel!
      authorize current_hotel, :update?, policy_class: HotelPolicy
    end

    def set_partner
      @partner = current_hotel.partners.find(params[:id])
    end

    def partner_params
      params.require(:partner).permit(:name, :code, :domain)
    end
  end
end
