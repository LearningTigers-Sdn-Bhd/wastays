# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RatePlanAttachments", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let!(:deluxe) { create(:room_type, hotel: hotel, name: "Deluxe Room", max_adults: 2) }
  let!(:villa) { create(:room_type, hotel: hotel, name: "Grand Villa", max_adults: 12) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(HotelPortal::BaseController).to receive(:current_hotel).and_return(hotel)
    allow_any_instance_of(HotelPortal::RatePlanAttachmentsController).to receive(:authorize).and_return(true)
  end

  it "requires hotel-management authorization" do
    allow_any_instance_of(HotelPortal::RatePlanAttachmentsController)
      .to receive(:authorize)
      .and_raise(Pundit::NotAuthorizedError)

    get new_hotel_rate_plan_attachment_path(hotel)

    expect(response).to redirect_to(root_path)
  end

  describe "GET #new" do
    it "renders a compact sheet with autocomplete and multi-select only" do
      get new_hotel_rate_plan_attachment_path(hotel, room_type_id: villa.id)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      sheet = document.at_css("#assign-room-rate-sheet")
      expect(sheet).to be_present
      expect(sheet.text.squish).to include("Assign Room Rate", "Assign room rate")
      expect(sheet.at_css(".panel-autocomplete input[name='rate_plan_attachment[rate_plan_name]']")).to be_present

      rooms = sheet.at_css("select[name='rate_plan_attachment[room_type_ids][]'][multiple]")
      expect(rooms).to be_present
      expect(rooms.css("option[selected]").map { |option| option["value"] }).to eq([ villa.id.to_s ])
      expect(sheet.text).not_to match(/Guest pricing|Occupancy pricing|Pricing mode/)
    end
  end

  describe "GET #autocomplete" do
    it "returns autocomplete results in the component response envelope" do
      results = [ { id: 42, label: "Weekend Rate", description: "Used by 2 room categories" } ]
      allow(RatePlans::Autocomplete).to receive(:call)
        .with(hotel: hotel, query: "week", limit: 20)
        .and_return(results)

      get autocomplete_hotel_rate_plan_attachments_path(hotel), params: { q: "week" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("results" => [
        "id" => 42,
        "label" => "Weekend Rate",
        "description" => "Used by 2 room categories"
      ])
    end
  end

  describe "POST #create" do
    let(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, name: "Weekend Rate") }

    it "delegates one relationship-only request and completes the sheet" do
      result = RatePlans::Attach::Result.new(
        rate_plan: rate_plan,
        attached_rooms: [ deluxe, villa ],
        error: nil
      )
      allow(RatePlans::Attach).to receive(:call).and_return(result)

      post hotel_rate_plan_attachments_path(hotel), params: {
        rate_plan_attachment: {
          rate_plan_id: rate_plan.id,
          rate_plan_name: rate_plan.name,
          room_type_ids: [ deluxe.id, villa.id ]
        }
      }, as: :turbo_stream

      expect(RatePlans::Attach).to have_received(:call).with(
        hotel: hotel,
        user: user,
        rate_plan_id: rate_plan.id.to_s,
        rate_plan_name: rate_plan.name,
        room_type_ids: [ deluxe.id.to_s, villa.id.to_s ]
      )
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include(hotel_room_types_path(hotel))
    end

    it "re-renders the sheet with the submitted context when attachment fails" do
      result = RatePlans::Attach::Result.new(
        rate_plan: nil,
        attached_rooms: [],
        error: "Select at least one room category."
      )
      allow(RatePlans::Attach).to receive(:call).and_return(result)

      post hotel_rate_plan_attachments_path(hotel), params: {
        rate_plan_attachment: {
          rate_plan_name: "Weekend Rate",
          room_type_ids: [ villa.id ]
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      document = response.parsed_body
      expect(document.at_css("[role='alert']").text.squish).to include("Select at least one room category")
      expect(document.at_css("input[name='rate_plan_attachment[rate_plan_name]']")["value"]).to eq("Weekend Rate")
      expect(document.at_css("select[name='rate_plan_attachment[room_type_ids][]'] option[selected]")["value"]).to eq(villa.id.to_s)
    end
  end
end
