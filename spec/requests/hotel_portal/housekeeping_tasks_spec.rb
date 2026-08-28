require "rails_helper"
require "pdf-reader"

RSpec.describe "Hotel portal housekeeping room board", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account:, status: "live", plan:) }
  let(:business_date) { hotel.current_business_date }
  let(:user) { create(:user, account:, role: "admin") }
  let(:role) { create(:role, account:, slug: "front_desk", name: "Front Desk") }
  let!(:room_type) do
    create(:room_type, hotel:, room_number_mode: "custom", quantity: 3, room_numbers: %w[101 202 303])
  end

  before do
    grant("dispatch_housekeeping_tasks")
    grant("perform_housekeeping_tasks")
    UserRole.find_or_create_by!(user:, role:)
    UserHotelAccess.find_or_create_by!(user:, hotel:, role:)
    create(
      :plan_feature,
      plan:,
      feature: create(:feature, feature_group:, slug: "task_assignment_minibar_log"),
      enabled: true
    )
    sign_in_as(user)
  end

  def grant(*slugs)
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
  end

  def regrant(*slugs)
    role.role_permissions.destroy_all
    grant(*slugs)
  end

  def active_housekeeper(name: "Siti Aminah")
    housekeeper_role = create(:role, account:, slug: "housekeeper", name: "Housekeeper")
    staff = create(:user, account:, name:)
    UserHotelAccess.create!(user: staff, hotel:, role: housekeeper_role)
    staff
  end

  def room_status(number, status: "dirty", **attributes)
    create(:room_status, hotel:, room_type:, room_number: number, status:, **attributes)
  end

  def stay(number:, status:, check_in:, check_out:, **attributes)
    booking = create(:booking, hotel:, status:, check_in:, check_out:, **attributes)
    create(:booking_room, booking:, room_type:, room_number: number)
    booking
  end

  describe "GET /hotel/:hotel_id/housekeeping_tasks" do
    it "renders one operational row per room with the revised columns and no task controls" do
      stay(
        number: "101",
        status: "checked_in",
        check_in: business_date - 1.day,
        check_out: business_date,
        adults: 2,
        children: 1
      )
      room_status("101", notes: "Guest requested extra towels")

      get hotel_housekeeping_tasks_path(hotel, date: business_date)

      expect(response).to have_http_status(:ok)
      header = response.body[/<thead>.*?<\/thead>/m]
      headers = Nokogiri::HTML.fragment(header).css("th").map { |column| column.text.squish }
      expect(headers).to include("Room", "Pax", "Nights", "Remarks")
      expect(headers[2]).to include("Room type", "All room types")
      expect(headers[3]).to include("Room group", "All room groups", "Ungrouped")
      expect(headers[5]).to include("Room status", "All room statuses")
      expect(headers[6]).to include("Assigned to", "All staff")
      expect(headers[7]).to include("Booking status", "All booking statuses")
      expect(headers[8]).to include("Arrival")
      expect(headers[9]).to include("Departure")
      expect(response.body).to include("2/1", "Guest requested extra towels", "Pending checkout")
      expect(response.body).to include("Clear remarks for #{room_type.name} 101")
      expect(response.body).not_to include("Task status", "Add task", "No task")
      expect(response.body.scan(/id="hk-room-#{room_type.id}-101"/).size).to eq(1)
      expect(response.body).to include("Select all visible rooms", "Select #{room_type.name} 101")

      document = Nokogiri::HTML(response.body)
      board = document.at_css('[data-controller~="housekeeping-table"]')
      expect(board["data-action"]).to include("change->housekeeping-table#changed")
      expect(document.at_css("table")["data-controller"]).to be_nil
      expect(document.css('a[data-action="click->housekeeping-table#navigate"]')).to all(
        satisfy { |link| link["data-turbo-frame"] == "housekeeping_tasks_results" }
      )
      expect(document.at_css("#hk-room-status-filter-trigger")["data-variant"]).to eq("ghost")
      expect(document.at_css("#hk-room-status-filter-trigger")["aria-label"]).to eq("Filter room status, all selected")
      badge = document.at_css("#hk-room-status-filter-cell .panel-badge")
      expect(badge.text).to eq("All")
      expect(badge["data-variant"]).to eq("primary")
    end

    it "uses styled selection controls and exact room-keyed mutation routes" do
      room_status("101")
      room_status("202", status: "cleaning")

      get hotel_housekeeping_tasks_path(hotel, date: business_date)

      selects = response.body.scan(/<select[^>]*>/)
      expect(selects).to be_present
      expect(selects).to all(match(/panel-select-menu__native|panel-combobox__native/))
      expect(response.body).to include(
        hotel_housekeeping_room_status_path(hotel, room_type_id: room_type.id, room_number: "101"),
        hotel_housekeeping_room_assignment_path(hotel, room_type_id: room_type.id, room_number: "101"),
        hotel_edit_housekeeping_room_remarks_path(hotel, room_type_id: room_type.id, room_number: "101")
      )

      document = Nokogiri::HTML(response.body)
      dirty_options = document.css("#hk-room-status-#{room_type.id}-101 option")
      cleaning_options = document.css("#hk-room-status-#{room_type.id}-202 option")
      status_form = document.at_css("#hk-room-status-#{room_type.id}-202").ancestors("form").first

      expect(dirty_options.map(&:text)).not_to include("Awaiting inspection", "Inspection failed")
      expect(dirty_options.find { |option| option.text == "Late checkout detected" }["disabled"]).to eq("disabled")
      expect(cleaning_options.map(&:text)).to include("Awaiting inspection", "Inspection failed")
      expect(cleaning_options.find { |option| option["value"] == "ready" }).to have_attributes(
        text: "Cleaned"
      )
      expect(status_form["data-turbo-frame"]).to eq("_top")
    end

    it "filters by room type and status and keeps sorting on export links" do
      other_room_type = create(:room_type, hotel:, room_number_mode: "custom", quantity: 1, room_numbers: %w[401])
      staff = active_housekeeper
      room_status("101", status: "dirty", assigned_to: staff)
      room_status("202", status: "ready")
      create(:room_status, hotel:, room_type: other_room_type, room_number: "401", status: "dirty")
      stay(number: "101", status: "checked_in", check_in: business_date - 1.day, check_out: business_date)

      get hotel_housekeeping_tasks_path(
        hotel,
        room_type_ids: [ room_type.id ],
        room_statuses: [ "dirty" ],
        assigned_to_ids: [ staff.id ],
        booking_statuses: [ "pending_checkout" ],
        sort: "arrival",
        direction: "desc",
        date: business_date - 1.day
      )

      table_body = response.body[/<tbody.*?<\/tbody>/m]
      table_document = Nokogiri::HTML.fragment(table_body)
      room_numbers = table_document.css('tr[data-housekeeping-room-row] th[data-column-key="room_number"] > div > span:first-child').map(&:text)
      expect(room_numbers).to eq([ "101" ])
      expect(table_body).to include("Pending checkout")
      expect(response.body).to include('aria-sort="descending"')
      %w[export-pdf-link export-excel-link export-csv-link].each do |link_id|
        href = CGI.unescapeHTML(response.body[/id="#{link_id}" href="([^"]*)"/, 1])
        expect(href).to include(
          "room_type_ids%5B%5D=#{room_type.id}",
          "room_statuses%5B%5D=dirty",
          "assigned_to_ids%5B%5D=#{staff.id}",
          "booking_statuses%5B%5D=pending_checkout",
          "sort=arrival",
          "direction=desc",
          "date=#{business_date}"
        )
      end
    end

    it "renders today's board without search or date controls" do
      room_status("202", notes: "Bring hypoallergenic pillows")

      get hotel_housekeeping_tasks_path(hotel, q: "HYPOALLERGENIC", date: business_date - 1.day)

      table_body = response.body[/<tbody.*?<\/tbody>/m]
      expect(table_body).to include("101", "202", "303", "Bring hypoallergenic pillows")
      expect(response.body).not_to include(
        'id="hk-filters-form"', 'name="q"', "Room, guest, booking or remarks", "As of date",
        "read-only outside the current business date"
      )
    end

    it "groups the board by room group and filters by it" do
      main_wing = create(:room_group, hotel:, name: "Main Wing")
      # The room type factory already made the physical rooms. Group two of them.
      hotel.rooms.where(number: %w[101 202]).find_each { |room| room.update!(room_group: main_wing) }

      get hotel_housekeeping_tasks_path(hotel, date: business_date, group_by: "room_group")

      document = Nokogiri::HTML(response.body)
      sections = document.css("tr[data-housekeeping-section-row] th").map { |cell| cell.text.squish }
      expect(sections).to eq([ "Main Wing 2 rooms", "Ungrouped 1 room" ])
      expect(document.css("tr[data-housekeeping-room-row]").size).to eq(3)

      section_rows = document.css("tr[data-housekeeping-section-row]")
      expect(section_rows.map { |row| row["data-housekeeping-section"] }).to eq(%w[hk-section-1 hk-section-2])
      expect(section_rows.first.at_css("input[data-housekeeping-section-select]")["id"]).to eq("select-hk-section-1")
      expect(section_rows.first.text.squish).to include("Select the 2 rooms in Main Wing", "Main Wing", "2 rooms")
      expect(section_rows[1].text.squish).to include("Select the 1 room in Ungrouped")
      expect(document.css("tr[data-housekeeping-room-row]").map { |row| row["data-housekeeping-section"] })
        .to eq(%w[hk-section-1 hk-section-1 hk-section-2])

      get hotel_housekeeping_tasks_path(hotel, date: business_date)
      flat = Nokogiri::HTML(response.body)
      expect(flat.css("tr[data-housekeeping-section-row]")).to be_empty
      expect(flat.css("tr[data-housekeeping-room-row]").map { |row| row["data-housekeeping-section"] })
        .to all(be_blank)

      get hotel_housekeeping_tasks_path(hotel, date: business_date, room_group_ids: [ main_wing.id ])
      filtered = Nokogiri::HTML(response.body)
      expect(filtered.css("tr[data-housekeeping-room-row]").map { |row| row["id"] }).to eq(
        [ "hk-room-#{room_type.id}-101", "hk-room-#{room_type.id}-202" ]
      )

      get hotel_housekeeping_tasks_path(hotel, date: business_date, room_group_ids: [ "__ungrouped__" ])
      ungrouped = Nokogiri::HTML(response.body)
      expect(ungrouped.css("tr[data-housekeeping-room-row]").map { |row| row["id"] }).to eq(
        [ "hk-room-#{room_type.id}-303" ]
      )
    end

    it "carries the room group into the exports" do
      main_wing = create(:room_group, hotel:, name: "Main Wing")
      hotel.rooms.find_by!(number: "101").update!(room_group: main_wing)

      get hotel_housekeeping_tasks_path(hotel, format: :csv),
          params: { date: business_date, group_by: "room_group" }

      rows = response.body.lines.map(&:strip)
      expect(rows.first).to include("Room Group")
      expect(rows[1..].map { |row| row.split(",")[2] }).to eq([ "Main Wing", "Ungrouped", "Ungrouped" ])
    end

    it "counts the selected filters in the column header badge" do
      main_wing = create(:room_group, hotel:, name: "Main Wing")
      hotel.rooms.find_by!(number: "101").update!(room_group: main_wing)

      get hotel_housekeeping_tasks_path(hotel, date: business_date, room_group_ids: [ main_wing.id ])

      document = Nokogiri::HTML(response.body)
      badge = document.at_css("#hk-room-group-filter-cell .panel-badge")
      expect(badge.text).to eq("1")
      expect(badge["aria-label"]).to eq("1 room groups selected")
      expect(badge["data-housekeeping-filter-badge"]).to eq("room_group_ids[]")
      expect(badge["data-housekeeping-filter-title"]).to eq("room group")
      expect(badge["data-housekeeping-filter-noun"]).to eq("room groups")
      expect(document.at_css("#hk-room-group-filter-trigger")["aria-label"])
        .to eq("Filter room group, 1 selected")

      get hotel_housekeeping_tasks_path(hotel, date: business_date, room_group_ids: [ "__none__" ])

      empty = Nokogiri::HTML(response.body)
      expect(empty.at_css("#hk-room-group-filter-cell .panel-badge").text).to eq("0")
      expect(empty.at_css("#hk-room-group-filter-trigger")["aria-label"])
        .to eq("Filter room group, 0 selected")
    end

    it "keeps header filters available when no rooms match" do
      get hotel_housekeeping_tasks_path(hotel, room_statuses: [ "__none__" ])

      expect(response.body).to include('id="hk-room-type-filter"', 'id="hk-room-status-filter"',
                                       'id="hk-room-group-filter"', "No rooms found")
      empty_state = Nokogiri::HTML(response.body).at_css("tbody td[colspan='12']")
      expect(empty_state.text.squish).to eq("No rooms found Change the filters to show rooms.")
    end

    it "exports every filtered room as CSV, XLSX, and PDF" do
      room_status("101", notes: "Inspect balcony")
      stay(number: "101", status: "checked_in", check_in: business_date - 1.day, check_out: business_date)

      export_params = {
        date: business_date - 1.day,
        room_type_ids: [ room_type.id ],
        room_statuses: [ "dirty" ]
      }

      get hotel_housekeeping_tasks_path(hotel, format: :csv), params: export_params
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Room Number,Room Type,Room Group,Pax", "Inspect balcony", "101", "Ungrouped")
      expect(response.body.lines.size).to eq(2)

      get hotel_housekeeping_tasks_path(hotel, format: :xlsx), params: export_params
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get hotel_housekeeping_tasks_path(hotel, format: :pdf), params: export_params
      text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(text).to include("Housekeeping Tasks", "Inspect balcony", user.name, "Page 1 of 1")
      expect(text).not_to include("ASSIGNED")
    end

    it "uses the current user's saved columns in the table and every export" do
      ReportViewPreference.create!(
        hotel:, user:, report_key: "housekeeping_tasks", visible_columns: %w[room_number remarks]
      )
      room_status("101", notes: "Inspect balcony")

      get hotel_housekeeping_tasks_path(hotel)
      header = Nokogiri::HTML(response.body).at_css("thead").text.squish
      expect(header).to include("Room", "Remarks")
      expect(header).not_to include("Room type", "Booking status", "Arrival")

      get hotel_housekeeping_tasks_path(hotel, format: :csv)
      expect(response.body.lines.first).to include("Room Number,Remarks")
      expect(response.body.lines.first).not_to include("Room Type")
    end

    it "exports only selected composite room identities" do
      room_status("101", notes: "Selected room")
      room_status("202", notes: "Not selected")

      get hotel_housekeeping_tasks_path(hotel, format: :csv), params: {
        selected_rooms: { room_type.id.to_s => [ "101" ] }
      }

      expect(response.body).to include("101", "Selected room")
      expect(response.body).not_to include("202", "Not selected")
    end

    it "returns an empty export when explicit room selections are invalid" do
      get hotel_housekeeping_tasks_path(hotel, format: :csv), params: {
        selected_rooms: { room_type.id.to_s => [ "not-a-room" ] }
      }

      expect(response.body.lines.size).to eq(1)
    end
  end

  describe "view preferences" do
    it "saves and resets the current user's visible columns" do
      patch hotel_housekeeping_view_preference_path(hotel),
        params: { visible_columns: %w[remarks room_number unknown] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("visible_columns")).to eq(%w[room_number remarks])
      preference = ReportViewPreference.find_by!(hotel:, user:, report_key: "housekeeping_tasks")
      expect(preference.visible_columns).to eq(%w[room_number remarks])

      delete hotel_housekeeping_view_preference_path(hotel), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("visible_columns")).to eq(HousekeepingTasks::Columns::KEYS)
      expect(preference.class.where(id: preference.id)).to be_empty
    end

    it "rejects an empty visible-column selection" do
      patch hotel_housekeeping_view_preference_path(hotel), params: { visible_columns: [] }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.fetch("error")).to eq("Keep at least one column visible.")
    end
  end

  describe "board authorization" do
    it "admits perform-only and dispatch-only users" do
      regrant("perform_housekeeping_tasks")
      get hotel_housekeeping_tasks_path(hotel)
      expect(response).to have_http_status(:ok)

      regrant("dispatch_housekeeping_tasks")
      get hotel_housekeeping_tasks_path(hotel)
      expect(response).to have_http_status(:ok)
    end

    it "rejects a user without either housekeeping permission" do
      regrant("manage_requests")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end
  end

  describe "room-level mutations" do
    it "lets a performer change status without a task or assignment" do
      regrant("perform_housekeeping_tasks")
      status = room_status("101", status: "dirty", notes: "Starting room")

      patch hotel_housekeeping_room_status_path(hotel, room_type_id: room_type.id, room_number: "101"),
            params: { date: business_date, status: "cleaning" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(status.reload.status).to eq("cleaning")
    end

    it "lets a dispatcher assign an active housekeeper and preserves board filters" do
      staff = active_housekeeper

      patch hotel_housekeeping_room_assignment_path(hotel, room_type_id: room_type.id, room_number: "101"), params: {
        date: business_date,
        assigned_to_id: staff.id,
        filters: {
          room_type_ids: [ room_type.id ],
          room_statuses: [ "dirty" ],
          assigned_to_ids: [ staff.id ],
          booking_statuses: [ "pending_checkout" ],
          sort: "arrival",
          direction: "desc",
          host: "evil.example"
        }
      }

      expect(response).to redirect_to(
        hotel_housekeeping_tasks_path(
          hotel,
          room_type_ids: [ room_type.id ],
          room_statuses: [ "dirty" ],
          assigned_to_ids: [ staff.id ],
          booking_statuses: [ "pending_checkout" ],
          sort: "arrival",
          direction: "desc"
        )
      )
      expect(RoomStatus.find_by!(hotel:, room_type:, room_number: "101").assigned_to).to eq(staff)
    end

    it "does not let a performer assign rooms" do
      regrant("perform_housekeeping_tasks")
      staff = active_housekeeper

      patch hotel_housekeeping_room_assignment_path(hotel, room_type_id: room_type.id, room_number: "101"),
            params: { date: business_date, assigned_to_id: staff.id }

      expect(response).to redirect_to(root_path)
      expect(RoomStatus.find_by(hotel:, room_type:, room_number: "101")).to be_nil
    end

    it "opens and updates focused room remarks" do
      return_to = hotel_housekeeping_tasks_path(hotel)

      get hotel_edit_housekeeping_room_remarks_path(hotel, room_type_id: room_type.id, room_number: "101"),
          params: { date: business_date, return_to: }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        "Edit housekeeping remarks", "Save remarks", CGI.escapeHTML(return_to), 'data-turbo-frame="_top"'
      )

      patch hotel_housekeeping_room_remarks_path(hotel, room_type_id: room_type.id, room_number: "101"),
            params: { date: business_date, notes: "Guest still has luggage", return_to: }

      expect(response).to redirect_to(return_to)
      expect(RoomStatus.find_by!(hotel:, room_type:, room_number: "101").notes).to eq("Guest still has luggage")
    end

    it "clears room remarks through the room-keyed update" do
      status = room_status("101", notes: "Remove after inspection")

      patch hotel_housekeeping_room_remarks_path(hotel, room_type_id: room_type.id, room_number: "101"),
            params: { date: business_date, notes: "" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(status.reload.notes).to be_nil
      expect(RoomOperationalAuditLog.last.metadata).to include("old_notes" => "Remove after inspection")
    end

    it "rejects room mutation from a historical board" do
      status = room_status("101", status: "dirty")

      patch hotel_housekeeping_room_status_path(hotel, room_type_id: room_type.id, room_number: "101"),
            params: { date: business_date - 1.day, status: "cleaning" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(flash[:alert]).to eq("Housekeeping can only be updated for the current business date.")
      expect(status.reload.status).to eq("dirty")
    end

    it "rejects a room identity outside the current hotel" do
      other_hotel = create(:hotel, account:)
      other_type = create(:room_type, hotel: other_hotel, room_number_mode: "custom", quantity: 1, room_numbers: %w[101])

      patch hotel_housekeeping_room_status_path(hotel, room_type_id: other_type.id, room_number: "101"),
            params: { date: business_date, status: "dirty" }

      expect(response).to have_http_status(:not_found)
      expect(RoomStatus.find_by(hotel: other_hotel, room_type: other_type, room_number: "101")).to be_nil
    end
  end
end
