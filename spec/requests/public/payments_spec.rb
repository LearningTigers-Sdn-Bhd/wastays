require "rails_helper"
require "ostruct"

RSpec.describe "Public::Payments", type: :request do
  let(:hotel) { create(:hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel, total_amount: 321.55, currency: "MYR") }
  let(:guest_details) do
    {
      name: "Guest",
      email: "guest@example.com",
      phone: "+60123456789",
      government_id: "A1234567",
      gender: "male",
      country: "Malaysia",
      document_type: "ic",
      date_of_birth: "1990-05-20"
    }
  end

  describe "POST /payments/checkout_session" do
    it "returns checkout payload for frontend" do
      create(:payment_setting,
             settable: hotel,
             gateway: "razorpay",
             api_key: "rzp_test_key",
             secret_key: "rzp_test_secret",
             status: "active")

      adapter = instance_double("Payments::GatewayAdapters::Razorpay")
      allow(Payments::GatewayRegistry).to receive(:fetch).and_return(adapter)
      allow(adapter).to receive(:create_checkout_session).and_return(
        {
          key_id: "rzp_test_key",
          order_id: "order_123",
          amount: 32155,
          currency: "MYR"
        }
      )

      post "/payments/checkout_session", params: {
        quote_token: quote.token,
        gateway: "razorpay",
        guest_details: guest_details
      }

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["order_id"]).to eq("order_123")
      expect(body["key_id"]).to eq("rzp_test_key")
      expect(body["amount"]).to eq(32155)
    end

    it "uses credential default gateway when db settings are not present" do
      credential_setting = Payments::CredentialSetting::Setting.new(
        gateway: "razorpay",
        api_key: "rzp_test_key",
        secret_key: "rzp_test_secret",
        webhook_secret: "whsec",
        status: "active"
      )
      allow(Payments::CredentialSetting).to receive(:default).and_return(credential_setting)
      allow(Payments::CredentialSetting).to receive(:for_gateway).with("razorpay").and_return(credential_setting)

      adapter = instance_double("Payments::GatewayAdapters::Razorpay")
      allow(Payments::GatewayRegistry).to receive(:fetch).and_return(adapter)
      allow(adapter).to receive(:create_checkout_session).and_return(
        {
          key_id: "rzp_test_key",
          order_id: "order_456",
          amount: 32155,
          currency: "MYR"
        }
      )

      post "/payments/checkout_session", params: {
        quote_token: quote.token,
        guest_details: guest_details
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["order_id"]).to eq("order_456")
      expect(body["gateway"]).to eq("razorpay")
    end
  end

  describe "POST /payments/verify" do
    it "confirms booking after successful callback verification" do
      create(:payment_setting,
             settable: hotel,
             gateway: "razorpay",
             api_key: "rzp_test_key",
             secret_key: "rzp_test_secret",
             webhook_secret: "whsec",
             status: "active")

      adapter = instance_double("Payments::GatewayAdapters::Razorpay")
      allow(Payments::GatewayRegistry).to receive(:fetch).and_return(adapter)
      allow(adapter).to receive(:verify_client_callback).and_return(
        {
          status: "captured",
          external_reference: "pay_123",
          payment_method: "netbanking"
        }
      )

      booking = create(:booking, booking_quote: quote, hotel: hotel)
      result = OpenStruct.new(success?: true, booking: booking)
      allow(BookingEngine::ConfirmBooking).to receive(:new).and_return(double(call: result))

      expect do
        post "/payments/verify", params: {
          quote_token: quote.token,
          gateway: "razorpay",
          guest_details: guest_details,
          payment_response: {
            razorpay_payment_id: "pay_123",
            razorpay_order_id: "order_123",
            razorpay_signature: "sig_123"
          }
        }
      end.to change(PaymentTransaction, :count).by(1)

      expect(response).to redirect_to(booking_path(booking.confirmation_token))
      expect(flash[:notice]).to eq("Payment successful!")

      transaction = PaymentTransaction.order(:id).last
      expect(transaction.gateway).to eq("razorpay")
      expect(transaction.status).to eq("captured")
      expect(transaction.payment_method).to eq("netbanking")
      expect(transaction.external_reference).to eq("pay_123")
      expect(transaction.gateway_order_id).to eq("order_123")
    end

    it "redirects back to quote when verification fails" do
      create(:payment_setting,
             settable: hotel,
             gateway: "razorpay",
             api_key: "rzp_test_key",
             secret_key: "rzp_test_secret",
             status: "active")

      adapter = instance_double("Payments::GatewayAdapters::Razorpay")
      allow(Payments::GatewayRegistry).to receive(:fetch).and_return(adapter)
      allow(adapter).to receive(:verify_client_callback).and_return(
        {
          status: "failed",
          message: "Signature mismatch"
        }
      )

      post "/payments/verify", params: {
        quote_token: quote.token,
        gateway: "razorpay",
        guest_details: guest_details,
        payment_response: {
          razorpay_payment_id: "pay_123",
          razorpay_order_id: "order_123",
          razorpay_signature: "bad"
        }
      }

      expect(response).to redirect_to(quote_path(quote.token))
      expect(flash[:alert]).to include("Signature mismatch")
    end
  end

  describe "GET /payments/verify" do
    it "confirms booking for redirect-based success callbacks without guest_details payload" do
      create(:payment_setting,
             settable: hotel,
             gateway: "razorpay",
             api_key: "rzp_test_key",
             secret_key: "rzp_test_secret",
             status: "active")

      adapter = instance_double("Payments::GatewayAdapters::Razorpay")
      allow(Payments::GatewayRegistry).to receive(:fetch).and_return(adapter)
      allow(adapter).to receive(:verify_client_callback).and_return(
        {
          status: "captured",
          external_reference: "pay_123",
          payment_method: "netbanking",
          metadata: {
            guest_name: "Guest",
            guest_email: "guest@example.com",
            guest_phone: "+60123456789",
            government_id: "A1234567",
            gender: "male",
            country: "Malaysia",
            document_type: "ic",
            date_of_birth: "1990-05-20"
          }
        }
      )

      booking = create(:booking, booking_quote: quote, hotel: hotel)
      result = OpenStruct.new(success?: true, booking: booking)
      allow(BookingEngine::ConfirmBooking).to receive(:new).and_return(double(call: result))

      get "/payments/verify", params: {
        quote_token: quote.token,
        gateway: "razorpay",
        razorpay_payment_id: "pay_123",
        razorpay_order_id: "order_123",
        razorpay_signature: "sig_123"
      }

      expect(response).to redirect_to(booking_path(booking.confirmation_token))
      expect(flash[:notice]).to eq("Payment successful!")
    end
  end
end
