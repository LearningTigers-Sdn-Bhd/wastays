require "rails_helper"

RSpec.describe "Legacy public hotel URLs", type: :request do
  let(:hotel) { create(:hotel, status: "live") }

  around do |example|
    travel_to(Public::LegacyHotelUrlsController::DEPLOYED_ON) { example.run }
  end

  it "temporarily redirects a code-only hotel URL and preserves its query" do
    get "/hotels/#{hotel.unique_id}", params: { check_in: "2026-10-01", adults: 2 }

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq(
      "http://www.example.com#{hotel_path(hotel.unique_id, hotel.public_id)}?check_in=2026-10-01&adults=2"
    )
  end

  it "temporarily redirects a slug rate-calendar URL" do
    get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: "2026-10-01" }

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq(
      "http://www.example.com#{rate_calendar_hotel_path(hotel.unique_id, hotel.public_id, start_date: '2026-10-01')}"
    )
  end

  it "temporarily redirects a Concierge GET URL" do
    get "/concierge/#{hotel.slug}/contact", params: { source: "qr" }

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq(
      "http://www.example.com#{concierge_contact_path(hotel.unique_id, hotel.public_id, source: 'qr')}"
    )
  end

  it "uses a method-preserving redirect for a Concierge POST URL" do
    post "/concierge/#{hotel.unique_id}/requests", params: { kind: "housekeeping" }

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq(
      "http://www.example.com#{concierge_requests_path(hotel.unique_id, hotel.public_id)}"
    )
  end

  it "uses a method-preserving redirect for a Concierge DELETE URL" do
    delete "/concierge/#{hotel.unique_id}/chat"

    expect(response).to have_http_status(:temporary_redirect)
    expect(response.location).to eq(
      "http://www.example.com#{concierge_clear_chat_path(hotel.unique_id, hotel.public_id)}"
    )
  end

  it "logs only the route family, identifier type, and sunset date" do
    allow(Rails.logger).to receive(:info)

    get "/hotels/#{hotel.slug}"

    expect(Rails.logger).to have_received(:info).with(
      "legacy_public_hotel_url_redirect route_family=hotel identifier_type=slug sunset_on=2026-12-14"
    )
  end

  it "returns 404 for an unknown legacy identifier" do
    get "/hotels/unknown-hotel"

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the transition has ended" do
    allow(Date).to receive(:current).and_return(Public::LegacyHotelUrlsController::SUNSET_ON)

    get "/hotels/#{hotel.unique_id}"

    expect(response).to have_http_status(:not_found)
  end
end
