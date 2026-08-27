# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomTypes", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:photo) { fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg") }

  before do
    # Simple auth mock
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(HotelPortal::BaseController).to receive(:current_hotel).and_return(hotel)

    # Mock Pundit
    allow_any_instance_of(HotelPortal::RoomTypesController).to receive(:authorize).and_return(true)

    room_type.photos.attach(photo)
  end

  describe "GET #index" do
    let!(:room_group) { create(:room_group, hotel: hotel) }
    let!(:grouped_room_type) { create(:room_type, hotel: hotel) }
    let!(:ungrouped_room_type) { create(:room_type, hotel: hotel) }

    it "lists rooms as a compact, default-closed inventory accordion with rate issues" do
      grouped_room_type.update!(description: "Description should not appear in the inventory row")
      ungrouped_room_type.update!(max_children: 0)
      custom_plan = create(:rate_plan, :custom, hotel: hotel, name: "Non-refundable", archived_at: Time.current)
      custom_assignment = create(
        :room_type_rate_plan,
        room_type: grouped_room_type,
        rate_plan: custom_plan,
        pricing_mode: "multiplier",
        pricing_value: -10
      )
      incomplete_plan = create(:rate_plan, :custom, hotel: hotel, name: "Advance purchase")
      incomplete_assignment = create(
        :room_type_rate_plan,
        room_type: grouped_room_type,
        rate_plan: incomplete_plan,
        pricing_mode: "fixed",
        pricing_value: nil
      )

      get hotel_room_types_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "Property Details Settings" ])
      expect(document.at_css("h2#room-inventory-heading").text.squish).to eq("Room Inventory")
      expect(document.at_css("[aria-label='Room categories and rate plans']")).to be_present

      accordion = document.at_css("#room-inventory-accordion")
      expect(accordion["data-panels-ui--accordion-type-value"]).to eq("single")
      expect(accordion["data-panels-ui--accordion-collapsible-value"]).to eq("true")
      expect(accordion["aria-label"]).to eq("Room inventory")
      expect(document.css("[data-room-type-id]")).to all(satisfy { |room| room["data-state"] == "closed" })
      expect(document.css("[data-room-type-id] .panel-collapsible__content")).to all(
        satisfy { |content| content.key?("hidden") && content.key?("inert") }
      )

      room_trigger = document.at_css("#room-inventory-#{grouped_room_type.id} .panel-collapsible__trigger")
      expect(room_trigger["aria-expanded"]).to eq("false")
      expect(room_trigger["aria-controls"]).to eq("room-inventory-#{grouped_room_type.id}-content")
      expect(document.css("[aria-label='Room categories and rate plans'] > div:first-child > span").map { |header| header.text.squish }).to eq(
        [ "Room category", "Capacity", "Rooms", "Rate issues", "Actions" ]
      )
      expect(document.at_css("#room-inventory-#{grouped_room_type.id} [aria-label='1 Adult'] svg")).to be_present
      expect(document.at_css("#room-inventory-#{grouped_room_type.id} [aria-label='1 Child'] svg")).to be_present
      expect(document.at_css("#room-inventory-#{grouped_room_type.id} [aria-label='1 room'] svg")).to be_present
      expect(document.at_css("#room-inventory-#{ungrouped_room_type.id} [aria-label$='Child']")).to be_nil

      grouped_header = document.at_css("#room-inventory-#{grouped_room_type.id} > .panel-collapsible__header")
      expect(grouped_header.text.squish).not_to include("Description should not appear", grouped_room_type.base_price.to_s)
      expect(grouped_header.at_css("[aria-label='1 rate pricing issue'] svg")).to be_present
      expect(grouped_header.at_css("[aria-label='1 rate pricing issue']").text.squish).to eq("1")
      expect(document.at_css("#room-inventory-#{ungrouped_room_type.id} > .panel-collapsible__header").text.squish).to include("No issues")

      expected_room_names = [ room_type, grouped_room_type, ungrouped_room_type ].index_by { |room| room.id.to_s }
      document.css("[data-room-type-id]").each do |room|
        room_name = expected_room_names.fetch(room["data-room-type-id"]).name
        rate_plan_list = room.at_css("[role='list'][aria-label='Rate plans for #{room_name}']")

        expect(rate_plan_list).to be_present
        expect(rate_plan_list.css("[role='listitem']")).not_to be_empty
      end

      assignment_row = document.at_css("#room-inventory-rate-plan-#{custom_assignment.id}")
      expect(assignment_row.text.squish).to include("Non-refundable", "Archived", "Adjusts Standard Rate", "Ready", "Edit rate", "Detach rate")
      # An archived plan reads as off, and restoring is not confirmed — the
      # confirm belongs on the direction that takes a plan out of use.
      restore_form = assignment_row.at_css("form[action='#{unarchive_hotel_rate_plan_path(hotel, custom_plan, room_type_id: grouped_room_type.id)}']")
      expect(restore_form).to be_present
      expect(restore_form.at_css("input[name='_method']")["value"]).to eq("patch")
      expect(restore_form["data-turbo-confirm"]).to be_nil
      restore_switch = restore_form.at_css("input[role='switch']")
      expect(restore_switch["checked"]).to be_nil
      expect(assignment_row.text.squish).to include("Restore Non-refundable for #{grouped_room_type.name}")
      expect(assignment_row.at_css("button[aria-label='Actions for Non-refundable in #{grouped_room_type.name}']")).to be_present
      detach_action = assignment_row.css("button").find { |button| button.text.squish == "Detach rate" }
      expect(detach_action).to be_present
      expect(detach_action["data-turbo-confirm-tone"]).to eq("destructive")

      incomplete_row = document.at_css("#room-inventory-rate-plan-#{incomplete_assignment.id}")
      expect(incomplete_row.text.squish).to include("Advance purchase", "Not priced", "Needs pricing")
      archive_form = incomplete_row.at_css("form[action='#{archive_hotel_rate_plan_path(hotel, incomplete_plan, room_type_id: grouped_room_type.id)}']")
      expect(archive_form).to be_present
      expect(archive_form["data-turbo-confirm-title"]).to eq("Archive rate plan")
      expect(archive_form["data-turbo-confirm-tone"]).to eq("warning")
      # A declined confirm has to put the switch back — it has already moved by
      # the time the dialog opens.
      expect(archive_form["data-action"]).to include("panels-ui:confirm-settled->tax-registry-status#settled")
      expect(archive_form.at_css("input[role='switch']")["checked"]).to eq("checked")

      standard_assignment = grouped_room_type.room_type_rate_plans.find { |assignment| assignment.rate_plan.standard_rate? }
      standard_row = document.at_css("#room-inventory-rate-plan-#{standard_assignment.id}")
      expect(standard_row.text.squish).to include("Standard Rate", "Default", "MYR 99.99", "Ready")
      expect(standard_row.text.squish).not_to include("Standard Rate MYR", "Detach rate")
      # Every other plan prices against Standard, so the switch is locked on
      # rather than absent — the row still reads as having an availability slot,
      # and it can never post an archive request.
      expect(standard_row.at_css("form")).to be_nil
      standard_switch = standard_row.at_css("input[role='switch']")
      expect(standard_switch["disabled"]).to eq("disabled")
      expect(standard_switch["checked"]).to eq("checked")
      expect(standard_row.text.squish).to include("Standard Rate is the price anchor for #{grouped_room_type.name} and is always offered")

      system_rows = grouped_room_type.room_type_rate_plans.select { |assignment| assignment.rate_plan.kind.in?(%w[walk_in corporate]) }
      system_rows.each do |system_assignment|
        row = document.at_css("#room-inventory-rate-plan-#{system_assignment.id}")
        expect(row.text.squish).not_to include("Detach rate")
        form = row.at_css("form")
        expect(form["action"]).to eq(archive_hotel_rate_plan_path(hotel, system_assignment.rate_plan, room_type_id: grouped_room_type.id))
        expect(form.at_css("input[role='switch']")["disabled"]).to be_nil
      end

      # One switch per row on one page: a shared field name would generate one
      # shared id and every label would bind to the first row's control.
      switch_ids = document.css("input[role='switch']").map { |input| input["id"] }
      expect(switch_ids).to all(be_present)
      expect(switch_ids.uniq.size).to eq(switch_ids.size)

      rate_header = document.at_css("#room-inventory-#{grouped_room_type.id} [aria-label='Rate plan columns']")
      first_header_cell = rate_header.element_children.first
      expect(first_header_cell.text.squish).to eq("Rate availability")
      expect(first_header_cell.at_css(".sr-only")).to be_present
      expect(document.at_css("#room-inventory-#{grouped_room_type.id} h4").text.squish).to eq("Rate plans (5)")

      new_rate = document.css("#room-inventory-#{grouped_room_type.id} a").find { |link| link.text.squish == "New rate" }
      expect(new_rate["href"]).to eq(new_hotel_rate_plan_path(hotel, room_type_id: grouped_room_type.id))
      expect(document.at_css("body").text).to include("Rooms", "Rate issues", "Rate plans (5)", "New rate")
      expect(document.at_css("body").text).not_to include("New Rate", "Standard Rate (MYR)")
      expect(document.at_css("body").text).to include("Assign room rate")
      expect(document.at_css("body").text).not_to include("Assign Room Group", room_group.name)
      expect(document.css("a[aria-label^='Attach rate plan to']")).to be_empty
      expect(document.css(".dropdown-menu-root").count).to be >= 2
      expect(document.css("button[data-turbo-confirm-tone='destructive']").count).to be >= 2
      expect(document.at_css("body").text).not_to include("Total Categories")
    end

    it "does not filter Room Inventory by legacy room-group parameters" do
      another_group = create(:room_group, hotel: hotel)
      another_room = create(:room_type, hotel: hotel)

      get hotel_room_types_path(hotel), params: { room_group_ids: [ room_group.id, "unassigned" ] }

      ids = response.parsed_body.css("[data-room-type-id]").map { |row| row["data-room-type-id"] }
      expect(ids).to include(grouped_room_type.id.to_s, ungrouped_room_type.id.to_s)
      expect(ids).to include(another_room.id.to_s)
    end

    it "searches by room category and attached rate plan name without duplicate rows" do
      matching_plan = create(:rate_plan, :custom, hotel: hotel, name: "Weekend Escape")
      create(:room_type_rate_plan, room_type: grouped_room_type, rate_plan: matching_plan)
      second_matching_plan = create(:rate_plan, :custom, hotel: hotel, name: "Weekend Saver")
      create(:room_type_rate_plan, room_type: grouped_room_type, rate_plan: second_matching_plan)

      get hotel_room_types_path(hotel), params: { q: "WEEKEND" }

      ids = response.parsed_body.css("[data-room-type-id]").map { |row| row["data-room-type-id"] }
      expect(ids).to eq([ grouped_room_type.id.to_s ])
    end

    it "renders search without room-group assignment or filter controls" do
      get hotel_room_types_path(hotel)
      document = response.parsed_body
      expect(document.at_css("input[name='q']")).to be_present
      expect(document.at_css("select[name='room_group_ids[]'][multiple]")).to be_nil
      expect(document.at_css("nav[aria-label='Room Group Filter']")).to be_nil
      expect(document.text.squish).not_to include("Assign Room Group")
    end

    it "paginates search results at 25 and retains the search" do
      create_list(:room_type, 26, hotel: hotel, name: "Searchable Category")

      get hotel_room_types_path(hotel), params: { q: "Searchable" }

      document = response.parsed_body
      expect(document.css("[data-room-type-id]").size).to eq(25)
      page_two = document.css("a").find { |link| link.text.squish == "2" }
      query = Rack::Utils.parse_nested_query(URI.parse(page_two["href"]).query)
      expect(query).to include("q" => "Searchable", "page" => "2")
      expect(query).not_to have_key("room_group_ids")
    end
  end

  describe "GET #new" do
    it "renders a right xl single-column sheet without photo controls" do
      reserved_type = create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "305" ])
      create(:room, hotel: hotel, room_type: reserved_type, number: "450", archived_at: 1.day.ago)

      get new_hotel_room_type_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      sheet = document.at_css("dialog#new-room-category-sheet")
      form = document.at_css("form#new-room-category-form")
      basics_fields = document.at_css("section[aria-labelledby='room-category-basics-heading'] > div:nth-child(2)")
      capacity_fields = document.at_css("section[aria-labelledby='room-category-capacity-heading'] > div:nth-child(2)")
      restriction_fields = document.at_css("section[aria-labelledby='room-category-restrictions-heading'] > div:nth-child(2)")

      expect(sheet["data-panels-ui--sheet-dismissible-value"]).to eq("false")
      expect(sheet["class"].split).to include("right-0", "w-[48rem]")
      expect(sheet["class"].split).not_to include("left-0", "bottom-0", "w-dvw")
      expect(form["class"].split).to include("space-y-8")
      expect(form["class"].split).not_to include("lg:grid-cols-2")
      expect(form["data-room-number-generator-default-start-value"]).to eq("451")
      expect(JSON.parse(form["data-room-number-generator-reserved-numbers-value"])).to contain_exactly("305", "450")
      expect(basics_fields["class"].split).not_to include("sm:grid-cols-2")
      expect(capacity_fields["class"].split).to include("sm:grid-cols-2")
      expect(restriction_fields["class"].split).to include("sm:grid-cols-2")
      expect(document.at_css("[class~='sm:col-span-2']")).to be_nil

      %w[basics capacity amenities restrictions numbering].each do |section|
        expect(document.at_css("#room-category-#{section}-heading")).to be_present
      end
      expect(document.at_css("#room-category-photos-heading")).to be_nil
      expect(document.at_css("#room-type-photos-manager")).to be_nil
      expect(document.at_css("#bulk-delete-photos-form")).to be_nil
      expect(document.at_css("input[type='file']")).to be_nil
      expect(document.at_css('[data-panels-ui--tabs-target="tab"]')).to be_nil
      expect(document.at_css("select[name='room_type[room_group_id]']")).to be_nil
    end
  end

  describe "GET #edit" do
    it "retains the full bottom two-column sheet with photo management" do
      room_type.update!(quantity: 1, room_numbers: [ "101" ])
      create(:room, hotel: hotel, room_type: room_type, number: "101")
      other_type = create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "201" ])
      create(:room, hotel: hotel, room_type: other_type, number: "202", archived_at: 1.day.ago)

      get edit_hotel_room_type_path(hotel, room_type)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      sheet = document.at_css("dialog#edit-room-category-sheet")
      form = document.at_css("form#edit-room-category-#{room_type.id}-form")
      restriction_fields = document.at_css("section[aria-labelledby='room-category-restrictions-heading'] > div:nth-child(2)")
      rendered_classes = form.css("[class]").flat_map { |element| element["class"].split }

      expect(sheet["data-panels-ui--sheet-dismissible-value"]).to eq("false")
      expect(sheet["class"].split).to include("bottom-0", "h-dvh", "rounded-none")
      expect(sheet["class"].split).not_to include("left-0", "w-[48rem]")
      expect(form["class"].split).to include("lg:grid-cols-2")
      expect(form["data-room-number-generator-default-start-value"]).to eq("203")
      expect(JSON.parse(form["data-room-number-generator-reserved-numbers-value"])).to contain_exactly("201", "202")
      expect(rendered_classes).to include("sm:grid-cols-2", "sm:col-span-2")
      expect(restriction_fields["class"].split).to include("sm:grid-cols-2")
      expect(document.at_css("#room-category-photos-heading")).to be_present
      expect(document.at_css("#room-type-photos-manager")).to be_present
      expect(document.at_css("#bulk-delete-photos-form")).to be_present
      expect(document.at_css("input[type='file']")).to be_present
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      { room_type: { name: "Deluxe Twin", max_adults: 2, max_children: 1, quantity: 3, base_price: 250, room_number_mode: "range" } }
    end

    it "closes the sheet and returns to the list" do
      expect {
        post hotel_room_types_path(hotel), params: valid_params, as: :turbo_stream
      }.to change(RoomType, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="settings_action_sheet"')
      expect(response.body).to include(hotel_room_types_path(hotel))
    end

    it "ignores a room-group assignment, because a group holds rooms and not categories" do
      room_group = create(:room_group, hotel: hotel)

      expect do
        post hotel_room_types_path(hotel),
             params: { room_type: valid_params[:room_type].merge(room_group_id: room_group.id) },
             as: :turbo_stream
      end.to change(RoomType, :count).by(1)

      expect(RoomType.column_names).not_to include("room_group_id")
    end

    it "re-renders the sheet with the errors when the category is invalid" do
      post hotel_room_types_path(hotel), params: { room_type: valid_params[:room_type].merge(name: "") }

      expect(response).to have_http_status(:unprocessable_content)
      document = response.parsed_body
      sheet = document.at_css("dialog#new-room-category-sheet")
      form = document.at_css("form#new-room-category-form")

      expect(sheet["class"].split).to include("right-0", "w-[48rem]")
      expect(form["class"].split).to include("space-y-8")
      expect(document.at_css("#room-category-photos-heading")).to be_nil
      expect(response.body).to include("Name can&#39;t be blank")
    end
  end

  describe "PATCH #update" do
    it "closes the sheet and returns to the list" do
      patch hotel_room_type_path(hotel, room_type),
            params: { room_type: { name: "Renamed Category" } },
            as: :turbo_stream

      expect(room_type.reload.name).to eq("Renamed Category")
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="settings_action_sheet"')
    end

    it "re-renders the sheet with the errors when the category is invalid" do
      patch hotel_room_type_path(hotel, room_type), params: { room_type: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      document = response.parsed_body
      sheet = document.at_css("dialog#edit-room-category-sheet")
      form = document.at_css("form#edit-room-category-#{room_type.id}-form")

      expect(sheet["class"].split).to include("bottom-0", "h-dvh")
      expect(form["class"].split).to include("lg:grid-cols-2")
      expect(document.at_css("#room-category-photos-heading")).to be_present
      expect(response.body).to include("Name can&#39;t be blank")
    end
  end

  describe "DELETE #destroy_photo" do
    let(:photo_attachment) { room_type.photos.first }

    it "deletes a photo and replaces only the photo grid" do
      expect {
        delete destroy_photo_hotel_room_type_path(hotel, room_type, photo_id: photo_attachment.id), as: :turbo_stream
      }.to change { room_type.photos.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="room-type-photos-manager"')
      expect(response.body).to include("Selected photos deleted successfully.")
      # The surrounding form must not be re-rendered, or unsaved edits are lost.
      expect(response.body).not_to include("room-category-basics-heading")
    end

    it "redirects to the list for a non-Turbo request" do
      delete destroy_photo_hotel_room_type_path(hotel, room_type, photo_id: photo_attachment.id)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(flash[:notice]).to eq("Selected photos deleted successfully.")
    end
  end

  describe "DELETE #bulk_destroy_photos" do
    before do
      room_type.photos.attach(fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg"))
    end

    it "deletes multiple photos and replaces only the photo grid" do
      photo_ids = room_type.photos.pluck(:id)

      expect {
        delete bulk_destroy_photos_hotel_room_type_path(hotel, room_type), params: { photo_ids: photo_ids }, as: :turbo_stream
      }.to change { room_type.photos.count }.to(0)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="room-type-photos-manager"')
      expect(response.body).to include("Selected photos deleted successfully.")
    end

    it "reports back into the sheet when no photos were selected" do
      delete bulk_destroy_photos_hotel_room_type_path(hotel, room_type), params: { photo_ids: [] }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("No photos selected.")
    end
  end
end
