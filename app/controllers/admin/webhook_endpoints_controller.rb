# frozen_string_literal: true

module Admin
  class WebhookEndpointsController < Admin::BaseController
    before_action :set_webhook_endpoint, only: [ :update, :destroy, :test_ping, :toggle ]

    def index
      @webhook_endpoints = WebhookEndpoint.all.order(created_at: :desc)
      @webhook_endpoint = WebhookEndpoint.new
    end

    def create
      @webhook_endpoint = WebhookEndpoint.new(webhook_endpoint_params)

      if @webhook_endpoint.save
        redirect_to admin_webhook_endpoints_path, notice: "Webhook endpoint created successfully."
      else
        @webhook_endpoints = WebhookEndpoint.all.order(created_at: :desc)
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @webhook_endpoint.update(webhook_endpoint_params)
        redirect_to admin_webhook_endpoints_path, notice: "Webhook endpoint updated successfully."
      else
        @webhook_endpoints = WebhookEndpoint.all.order(created_at: :desc)
        render :index, status: :unprocessable_entity
      end
    end

    def toggle
      @webhook_endpoint.update(enabled: !@webhook_endpoint.enabled)
      status = @webhook_endpoint.enabled ? "enabled" : "disabled"
      redirect_to admin_webhook_endpoints_path, notice: "Webhook '#{@webhook_endpoint.name}' has been #{status}."
    end

    def destroy
      @webhook_endpoint.destroy
      redirect_to admin_webhook_endpoints_path, notice: "Webhook endpoint deleted."
    end

    def test_ping
      response = send_test_ping(@webhook_endpoint.url)

      if response.code.to_i.between?(200, 299)
        redirect_to admin_webhook_endpoints_path, notice: "Test ping to '#{@webhook_endpoint.name}' sent successfully (HTTP #{response.code})."
      else
        redirect_to admin_webhook_endpoints_path, alert: "Test ping to '#{@webhook_endpoint.name}' failed: HTTP #{response.code}."
      end
    rescue StandardError => e
      redirect_to admin_webhook_endpoints_path, alert: "Test ping failed: #{e.message}"
    end

    private

    def set_webhook_endpoint
      @webhook_endpoint = WebhookEndpoint.find(params[:id])
    end

    def webhook_endpoint_params
      params.require(:webhook_endpoint).permit(:name, :url, :enabled, :event_types)
    end

    def send_test_ping(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 10

      payload = {
        test: true,
        event: "test_ping",
        sent_at: Time.current.iso8601,
        message: "Hello from WAStays!"
      }

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = payload.to_json
      http.request(request)
    end
  end
end
