# frozen_string_literal: true

module HotelPortal
  class PartnersController < HotelPortal::BaseController
    before_action :authorize_hotel!
    before_action :set_partner, only: [ :update, :destroy ]

    def create
      partner = current_hotel.partners.new(partner_params)

      if partner.save
        redirect_back fallback_location: hotel_inventory_index_path(current_hotel), notice: "Partner created successfully."
      else
        redirect_back fallback_location: hotel_inventory_index_path(current_hotel), alert: partner.errors.full_messages.to_sentence
      end
    end

    def update
      if @partner.update(partner_params)
        redirect_back fallback_location: hotel_inventory_index_path(current_hotel), notice: "Partner updated successfully."
      else
        redirect_back fallback_location: hotel_inventory_index_path(current_hotel), alert: @partner.errors.full_messages.to_sentence
      end
    end

    def destroy
      @partner.destroy!
      redirect_back fallback_location: hotel_inventory_index_path(current_hotel), notice: "Partner deleted successfully."
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
