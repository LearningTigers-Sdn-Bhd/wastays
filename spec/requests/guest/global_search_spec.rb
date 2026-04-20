require "rails_helper"

RSpec.describe "Guest global search", type: :request do
  let(:guest) do
    create(:guest,
           name: "Search Guest",
           email: "search.guest@example.com",
           phone: "+60123456789",
           country: "Malaysia",
           document_type: "passport",
           government_id: "A1234567")
  end

  def sign_in_guest!(guest)
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
    expect(response).to redirect_to(guest_dashboard_path)
  end

  it "returns page search results for signed in guests" do
    sign_in_guest!(guest)

    get guest_global_search_index_path, params: { q: "" }, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    titles = json.fetch("results").map { |row| row.fetch("title") }

    expect(titles).to include("Guest Dashboard", "My Bookings")
  end
end
