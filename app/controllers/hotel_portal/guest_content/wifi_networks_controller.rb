# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class WifiNetworksController < HotelPortal::GuestContent::BaseController
      include SheetActionCompletion

      before_action :set_network, only: %i[edit update destroy quick_update]

      def index
        @networks = @hotel.hotel_wifi_networks.in_display_order
      end

      def new
        @network = @hotel.hotel_wifi_networks.build(position: @hotel.hotel_wifi_networks.maximum(:position).to_i + 1)
        render layout: false
      end

      def create
        @network = @hotel.hotel_wifi_networks.build
        persist_network(success_notice: "Wi-Fi network added successfully.", failure_view: :new)
      end

      def edit
        render layout: false
      end

      def update
        persist_network(success_notice: "Wi-Fi network updated successfully.", failure_view: :edit)
      end

      def destroy
        HotelPortal::DestroyWifiNetwork.new(hotel: @hotel, network: @network).call
        complete_sheet_action(
          destination: hotel_wifi_networks_path(@hotel),
          notice: "Wi-Fi network removed successfully.",
          frame: sheet_frame
        )
      end

      def quick_update
        if quick_network_params.key?(:active) && @network.primary_network?
          return redirect_to hotel_wifi_networks_path(@hotel), alert: "The primary Wi-Fi network must stay active."
        end

        service = HotelPortal::SaveWifiNetwork.new(hotel: @hotel, network: @network, attributes: quick_network_params)
        if service.call
          redirect_to hotel_wifi_networks_path(@hotel), notice: "Wi-Fi network updated successfully."
        else
          redirect_to hotel_wifi_networks_path(@hotel), alert: @network.errors.full_messages.to_sentence
        end
      end

      private

      def set_network
        @network = @hotel.hotel_wifi_networks.find(params[:id])
      end

      def persist_network(success_notice:, failure_view:)
        service = HotelPortal::SaveWifiNetwork.new(hotel: @hotel, network: @network, attributes: network_params)
        if service.call
          complete_sheet_action(
            destination: hotel_wifi_networks_path(@hotel),
            notice: success_notice,
            frame: sheet_frame
          )
        else
          render failure_view, formats: :html, layout: false, status: :unprocessable_content
        end
      end

      def quick_network_params
        params.require(:hotel_wifi_network).permit(:security_type, :access_scope, :active)
      end

      def network_params
        params.require(:hotel_wifi_network).permit(
          :label, :ssid, :password, :security_type, :connection_instructions,
          :access_scope, :primary_network, :active, :position
        )
      end

      def sheet_frame
        turbo_frame_request_id.presence || "settings_action_sheet"
      end
    end
  end
end
