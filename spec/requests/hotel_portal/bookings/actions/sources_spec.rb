# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions change source", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel:, guest_name: "Ada Lovelace", source: "phone") }
  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" } }

  def grant(*slugs)
    slugs.each do |slug|
      permission = Permission.find_by(slug:) || create(:permission, slug:, name: slug.tr("_", " ").titleize)
      create(:role_permission, role:, permission:)
    end
  end

  before do
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  context "with manage_bookings" do
    before { grant("manage_bookings", "view_bookings") }

    it "renders the source picker in the booking action Sheet" do
      get hotel_booking_action_change_source_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet dialog#booking-source-sheet")).to be_present
      select = document.at_css("select[name='booking[source]']")
      expect(select.at_css("option[selected]")["value"]).to eq("phone")
      expect(select.css("option").map { |option| option["value"] }).to include("booking_com", "walk_in")
      expect(select.css("option").map { |option| option["value"] }).not_to include("channex")
    end

    it "changes the source and completes the Sheet" do
      patch hotel_booking_action_change_source_path(hotel, booking),
        params: { booking: { source: "agoda" } }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"')
      expect(booking.reload.source).to eq("agoda")
    end

    it "keeps the Sheet open with the reason when the source is refused" do
      patch hotel_booking_action_change_source_path(hotel, booking),
        params: { booking: { source: "channex" } }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("booking-source-sheet", "Channex is not an available booking source.")
      expect(booking.reload.source).to eq("phone")
    end

    it "explains why a channel manager booking cannot be changed instead of offering the picker" do
      booking.update!(channel_manager_reference: "CHX-1")

      get hotel_booking_action_change_source_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response.body).to include("which owns its source")
      expect(Nokogiri::HTML(response.body).at_css("select[name='booking[source]']")).to be_nil
    end

    it "offers the action from the booking overview" do
      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

      expect(response.body).to include(hotel_booking_action_change_source_path(hotel, booking))
    end

    it "shows the change in the audit trail" do
      patch hotel_booking_action_change_source_path(hotel, booking), params: { booking: { source: "agoda" } }

      presenter = HotelPortal::BookingAuditLogPresenter.new(BookingAuditLog.find_by!(action_type: "source_changed"), hotel:)
      expect(presenter.title).to eq("Booking source changed")
      expect(presenter.summary).to eq("#{user.name} changed the booking source from Phone to Agoda.")
    end
  end

  it "refuses staff without manage_bookings" do
    grant("view_bookings")

    patch hotel_booking_action_change_source_path(hotel, booking), params: { booking: { source: "agoda" } }

    expect(booking.reload.source).to eq("phone")
    expect(response).not_to have_http_status(:success)
  end
end
