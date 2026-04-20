require "net/http"
require "uri"
require "json"

module Admin
  class IntegrationsController < Admin::BaseController
    def show
      @webhook_url = AppConfig.get("webhook_url")
    end

    def update
      AppConfig.set("webhook_url", params[:webhook_url].to_s.strip)
      redirect_to admin_integrations_path, notice: "Webhook URL saved successfully."
    end

    def destroy
      AppConfig.find_by(key: "webhook_url")&.destroy
      redirect_to admin_integrations_path, notice: "Webhook URL removed."
    end

    def test_ping
      url = AppConfig.get("webhook_url")

      unless url.present?
        redirect_to admin_integrations_path, alert: "No webhook URL configured. Save a URL first."
        return
      end

      response = send_test_ping(url)

      if response.code.to_i.between?(200, 299)
        redirect_to admin_integrations_path, notice: "Test ping sent successfully (HTTP #{response.code})."
      else
        redirect_to admin_integrations_path, alert: "Test ping failed: server returned HTTP #{response.code}."
      end
    rescue StandardError => e
      redirect_to admin_integrations_path, alert: "Test ping failed: #{e.message}"
    end

    private

    def send_test_ping(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 10

      payload = {
        test: true,
        confirmation_token: "TEST-PING",
        guest_name: "Test Guest",
        guest_phone: "+60000000000",
        guest_email: "test@wastays.com",
        hotel_name: "Test Hotel",
        check_in: Date.current.strftime("%Y-%m-%d"),
        check_out: (Date.current + 1.day).strftime("%Y-%m-%d"),
        nights: 1,
        total_amount: "0.00",
        currency: "MYR",
        invoice_url: "https://wastays.com/bookings/TEST-PING/invoice"
      }

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = payload.to_json
      http.request(request)
    end
  end
end
