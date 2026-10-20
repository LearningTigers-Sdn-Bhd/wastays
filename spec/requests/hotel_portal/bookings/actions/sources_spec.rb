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

    it "offers the hotel's travel agents behind the Travel Agent source" do
      agent = create(:hotel_corporate_account, hotel:, account_type: "travel_agent")
      company = create(:hotel_corporate_account, hotel:)

      get hotel_booking_action_change_source_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }

      panel = Nokogiri::HTML(response.body).at_css("[data-reveal-values='travel_agent']")
      expect(panel["hidden"]).not_to be_nil
      values = panel.css("select[name='booking[travel_agent_account_id]'] option").map { |option| option["value"] }
      expect(values).to include(agent.id.to_s)
      expect(values).not_to include(company.id.to_s)
    end

    it "puts the booking under the chosen agent" do
      agent = create(:hotel_corporate_account, hotel:, account_type: "travel_agent")

      patch hotel_booking_action_change_source_path(hotel, booking),
        params: { booking: { source: "travel_agent", travel_agent_account_id: agent.id } }, headers: turbo_headers

      expect(response.body).to include('action="complete_sheet"')
      expect(booking.reload).to have_attributes(source: "travel_agent", hotel_corporate_account_id: agent.id)
    end

    it "keeps the agent picker open when no agent was chosen" do
      create(:hotel_corporate_account, hotel:, account_type: "travel_agent")

      patch hotel_booking_action_change_source_path(hotel, booking),
        params: { booking: { source: "travel_agent" } }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose the travel agent this booking is under.")
      expect(Nokogiri::HTML(response.body).at_css("[data-reveal-values='travel_agent']")["hidden"]).to be_nil
    end

    it "offers to change the whole group, on by default, from a group room" do
      group = create(:group_booking, hotel:)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel:, group_booking: group, group_position: 2, source: "phone")

      get hotel_booking_action_change_source_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }
      expect(Nokogiri::HTML(response.body).at_css("input[type='checkbox'][name='booking[apply_to_group]'][checked]")).to be_present

      patch hotel_booking_action_change_source_path(hotel, booking),
        params: { booking: { source: "email", apply_to_group: "1" } }, headers: turbo_headers

      expect([ booking.reload.source, sibling.reload.source ]).to eq(%w[email email])
    end

    it "names the agent in the audit trail" do
      agent = create(:hotel_corporate_account, hotel:, account_type: "travel_agent")

      patch hotel_booking_action_change_source_path(hotel, booking),
        params: { booking: { source: "travel_agent", travel_agent_account_id: agent.id } }

      presenter = HotelPortal::BookingAuditLogPresenter.new(BookingAuditLog.find_by!(action_type: "source_changed"), hotel:)
      expect(presenter.summary).to eq("#{user.name} changed the booking source from Phone to Travel Agent (#{agent.corporate_account.name}).")
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
