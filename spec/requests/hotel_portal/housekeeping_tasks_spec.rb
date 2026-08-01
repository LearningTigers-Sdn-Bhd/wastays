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
    create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101 202 303])
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
      expect(Nokogiri::HTML.fragment(header).css("th").map { |column| column.text.squish }).to eq([
        "Room type", "Pax", "Room status", "Assigned to", "Booking status",
        "Arrival", "Departure", "Nights", "Remarks"
      ])
      expect(response.body).to include("2/1", "Guest requested extra towels", "Pending checkout")
      expect(response.body).to include("Clear remarks for #{room_type.name} 101")
      expect(response.body).not_to include("Task status", "Add task", "No task")
      expect(response.body.scan(/id="hk-group-#{room_type.id}-#{room_type.id}-101"/).size).to eq(1)
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
        text: "Cleaned — add remarks first"
      )
      expect(status_form["data-turbo-frame"]).to eq("_top")
    end

    it "filters by derived booking status and keeps the filter on export links" do
      stay(number: "101", status: "checked_in", check_in: business_date - 1.day, check_out: business_date)
      stay(number: "202", status: "confirmed", check_in: business_date, check_out: business_date + 2.days)

      get hotel_housekeeping_tasks_path(hotel, booking_status: "pending_checkout", date: business_date)

      table_body = response.body[/<tbody.*?<\/tbody>/m]
      expect(table_body).to include("101", "Pending checkout")
      expect(table_body).not_to include("Arriving today")
      %w[export-pdf-link export-excel-link export-csv-link].each do |link_id|
        href = CGI.unescapeHTML(response.body[/id="#{link_id}" href="([^"]*)"/, 1])
        expect(href).to include("booking_status=pending_checkout", "date=#{business_date}")
      end
    end

    it "searches current room remarks without requiring a task" do
      room_status("202", notes: "Bring hypoallergenic pillows")

      get hotel_housekeeping_tasks_path(hotel, q: "HYPOALLERGENIC", date: business_date)

      expect(response.body).to include("202", "Bring hypoallergenic pillows")
      expect(response.body).not_to include(">101<", ">303<")
    end

    it "renders historical dates read-only" do
      get hotel_housekeeping_tasks_path(hotel, date: business_date - 1.day)

      expect(response.body).to include("read-only outside the current business date")
      expect(response.body).not_to include(hotel_housekeeping_room_assignment_path(hotel, room_type_id: room_type.id, room_number: "101"))
      expect(response.body).not_to include(hotel_edit_housekeeping_room_remarks_path(hotel, room_type_id: room_type.id, room_number: "101"))
    end

    it "exports every filtered room as CSV, XLSX, and PDF" do
      room_status("101", notes: "Inspect balcony")

      get hotel_housekeeping_tasks_path(hotel, format: :csv), params: { date: business_date, q: "101" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Room Number,Room Type,Pax", "Inspect balcony", "101")
      expect(response.body.lines.size).to eq(2)

      get hotel_housekeeping_tasks_path(hotel, format: :xlsx), params: { date: business_date, q: "101" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get hotel_housekeeping_tasks_path(hotel, format: :pdf), params: { date: business_date, q: "101" }
      text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(text).to include("HOUSEKEEPING TASKS", "Inspect balcony", "Page 1 of 1")
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
        filters: { q: "101", booking_status: "vacant", date: business_date, host: "evil.example" }
      }

      expect(response).to redirect_to(
        hotel_housekeeping_tasks_path(hotel, q: "101", booking_status: "vacant", date: business_date.to_s)
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
      return_to = hotel_housekeeping_tasks_path(hotel, q: "101", date: business_date)

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
      other_type = create(:room_type, hotel: other_hotel, room_number_mode: "custom", room_numbers: %w[101])

      patch hotel_housekeeping_room_status_path(hotel, room_type_id: other_type.id, room_number: "101"),
            params: { date: business_date, status: "dirty" }

      expect(response).to have_http_status(:not_found)
      expect(RoomStatus.find_by(hotel: other_hotel, room_type: other_type, room_number: "101")).to be_nil
    end
  end
end
