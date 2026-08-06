require "rails_helper"

RSpec.describe "Guest navigation", type: :request do
  let(:guest) { create(:guest) }
  let(:booking) { create(:booking, confirmation_token: "WS-GUEST1", check_in: Date.current + 10.days) }

  before do
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
    create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0)
    sign_in_guest!(guest)
  end

  it "renders booking detail breadcrumbs with the confirmation token" do
    get guest_booking_path(booking)

    expect(response).to have_http_status(:success)
    expect(breadcrumb_labels).to eq([ "My Account", "My Bookings", "WS-GUEST1" ])
  end

  it "renders request-refund breadcrumbs under Refunds" do
    get new_guest_booking_refund_request_path(booking)

    expect(response).to have_http_status(:success)
    expect(breadcrumb_labels).to eq([ "My Account", "Refunds", "WS-GUEST1", "Request Refund" ])
  end

  it "renders refund detail breadcrumbs under Refunds" do
    refund_request = create(:refund_request, booking: booking)

    get guest_refund_request_path(refund_request)

    expect(response).to have_http_status(:success)
    expect(breadcrumb_labels).to eq([ "My Account", "Refunds", "WS-GUEST1", "Refund Details" ])
  end

  private

  def sign_in_guest!(record)
    otp = record.generate_otp!
    post guest_login_path, params: { phone: record.phone, otp: otp }
    expect(response).to redirect_to(guest_dashboard_path)
  end

  def breadcrumb_labels
    document = Nokogiri::HTML(response.body)
    bar = document.at_css("[data-controller='panels-ui--breadcrumb'] ol.breadcrumb-list")

    bar.element_children.filter_map do |segment|
      next unless segment["class"].to_s.split.include?("breadcrumb-item")

      content = segment.element_children.first
      current = if content&.name == "div"
        content.element_children.find { |node| %w[a span].include?(node.name) }
      else
        content
      end

      current&.text&.squish
    end
  end
end
