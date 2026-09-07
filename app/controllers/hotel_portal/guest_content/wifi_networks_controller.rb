# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class WifiNetworksController < HotelPortal::GuestContent::BaseController
      before_action :set_network, only: %i[edit update destroy]

      def index
        @networks = @hotel.hotel_wifi_networks.in_display_order
      end

      def new
        @network = @hotel.hotel_wifi_networks.build(position: @hotel.hotel_wifi_networks.maximum(:position).to_i + 1)
      end

      def create
        @network = @hotel.hotel_wifi_networks.build
        persist_network(success_notice: "Wi-Fi network added successfully.", failure_view: :new)
      end

      def edit; end

      def update
        persist_network(success_notice: "Wi-Fi network updated successfully.", failure_view: :edit)
      end

      def destroy
        HotelPortal::DestroyWifiNetwork.new(hotel: @hotel, network: @network).call
        redirect_to hotel_wifi_networks_path(@hotel), notice: "Wi-Fi network removed successfully."
      end

      private

      def set_network
        @network = @hotel.hotel_wifi_networks.find(params[:id])
      end

      def persist_network(success_notice:, failure_view:)
        service = HotelPortal::SaveWifiNetwork.new(hotel: @hotel, network: @network, attributes: network_params)
        if service.call
          redirect_to hotel_wifi_networks_path(@hotel), notice: success_notice
        else
          render failure_view, status: :unprocessable_content
        end
      end

      def network_params
        params.require(:hotel_wifi_network).permit(
          :label, :ssid, :password, :security_type, :connection_instructions,
          :access_scope, :primary_network, :active, :position
        )
      end
    end
  end
end
