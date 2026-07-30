require "rails_helper"
require "pdf-reader"

RSpec.describe "Hotel portal housekeeping tasks pages", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:permission) { Permission.find_or_create_by!(slug: "dispatch_housekeeping_tasks") { |record| record.name = "Dispatch Housekeeping Tasks" } }
  let(:requests_permission) { Permission.find_or_create_by!(slug: "manage_requests") { |record| record.name = "Manage Requests" } }
  let!(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101", "202", "303" ]) }

  before do
    RolePermission.find_or_create_by!(role: role, permission: permission)
    RolePermission.find_or_create_by!(role: role, permission: requests_permission)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/housekeeping-tasks" do
    it "renders the page successfully and lists in_progress housekeeping requests" do
      booking = create(:booking, hotel: hotel, guest_name: "John Doe", confirmation_token: "WS-HK123")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(
        :housekeeping_request,
        booking: booking,
        request_details: "Clean the sheets",
        status: "in_progress",
        room_number: "101"
      )

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Housekeeping Tasks")
      expect(response.body).to include("Clean the sheets")
      expect(response.body).to include("101")
    end

    it "shows open requests, including the pending ones nobody has triaged" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need water", status: "in_progress", room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need broom", status: "pending", room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need soap", status: "completed", room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need mop", status: "in_progress", room_number: "101", archived_at: Time.current)

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Need water")
      expect(response.body).to include("Need broom")
      expect(response.body).not_to include("Need soap")
      expect(response.body).not_to include("Need mop")
    end

    it "filters requests by room number via query parameter" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "202")
      create(:housekeeping_request, booking: booking, request_details: "Towels", room_number: "202", status: "in_progress")
      create(:housekeeping_request, booking: booking, request_details: "Soap", room_number: "303", status: "in_progress")

      get hotel_housekeeping_tasks_path(hotel, q: "202")

      expect(response.body).to include("Towels")
      expect(response.body).not_to include("Soap")
    end

    it "filters requests by assignee" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      staff1 = create(:user, account: account)
      staff2 = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff1, hotel: hotel, role: hk_role)
      UserHotelAccess.create!(user: staff2, hotel: hotel, role: hk_role)

      req1 = create(:housekeeping_request, booking: booking, room_number: "101", status: "in_progress", metadata: { "assigned_to" => staff1.id, "assigned_to_name" => staff1.name }, request_details: "Sheets")
      req2 = create(:housekeeping_request, booking: booking, room_number: "202", status: "in_progress", metadata: { "assigned_to" => staff2.id, "assigned_to_name" => staff2.name }, request_details: "Trash")

      get hotel_housekeeping_tasks_path(hotel, assigned_to: staff1.id)

      expect(response.body).to include("Sheets")
      expect(response.body).not_to include("Trash")
    end

    it "filters requests by room status" do
      group = create(:group_booking, hotel: hotel)
      dirty_room_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      ready_room_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_room, booking: dirty_room_booking, room_type: room_type, room_number: "101")
      create(:booking_room, booking: ready_room_booking, room_type: room_type, room_number: "202")

      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "202", status: "ready")

      create(:housekeeping_request, booking: dirty_room_booking, room_number: "101", status: "in_progress", request_details: "Sheets")
      create(:housekeeping_request, booking: ready_room_booking, room_number: "202", status: "in_progress", request_details: "Trash")

      get hotel_housekeeping_tasks_path(hotel, room_status: "dirty")

      expect(response.body).to include("Sheets")
      expect(response.body).not_to include("Trash")
    end

    it "resolves active booking for that day but does not filter housekeeping requests by date" do
      booking1 = create(:booking, hotel: hotel, check_in: Date.tomorrow.beginning_of_day, check_out: (Date.tomorrow + 2.days).end_of_day, guest_name: "Alice Smith")
      create(:booking_room, booking: booking1, room_type: room_type, room_number: "101")

      booking2 = create(:booking, hotel: hotel, check_in: Date.current.beginning_of_day, check_out: Date.tomorrow.end_of_day, guest_name: "Bob Jones")
      create(:booking_room, booking: booking2, room_type: room_type, room_number: "202")

      create(:housekeeping_request, booking: booking1, room_number: "101", status: "in_progress", request_details: "Sheets", requested_at: Date.tomorrow)
      create(:housekeeping_request, booking: booking2, room_number: "202", status: "in_progress", request_details: "Trash", requested_at: 2.days.ago)

      get hotel_housekeeping_tasks_path(hotel, date: Date.tomorrow.to_s)

      expect(response.body).to include("101")
      expect(response.body).to include(Date.tomorrow.strftime("%d %b %Y"))
      expect(response.body).to include("Sheets")
      expect(response.body).to include("Trash")
    end

    it "exports the filtered housekeeping board as csv, xlsx, and pdf" do
      selected_date = Date.new(2026, 7, 21)
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, room_number: "101", status: "in_progress", request_details: "Need water", requested_at: selected_date)
      create(:housekeeping_request, booking: booking, room_number: "202", status: "in_progress", request_details: "Fresh towels", requested_at: selected_date)

      get hotel_housekeeping_tasks_path(hotel, format: :csv), params: { date: selected_date, q: "101" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Need water")
      expect(response.body).not_to include("Fresh towels")
      expect(response.headers["Content-Disposition"]).to include("housekeeping-tasks-2026-07-21.csv")

      get hotel_housekeeping_tasks_path(hotel, format: :xlsx), params: { date: selected_date, q: "101" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")
      expect(response.headers["Content-Disposition"]).to include("housekeeping-tasks-2026-07-21.xlsx")

      get hotel_housekeeping_tasks_path(hotel, format: :pdf), params: { date: selected_date, q: "101" }
      pdf_text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(pdf_text).to include("HOUSEKEEPING TASKS", "Need water", "Page 1 of 1")
      expect(pdf_text).not_to include("Fresh towels")
    end

    it "points every export link at the filters the board was asked for" do
      get hotel_housekeeping_tasks_path(hotel), params: { q: "101", room_status: "dirty", date: "2026-07-21" }

      %w[export-pdf-link export-excel-link export-csv-link].each do |link_id|
        href = CGI.unescapeHTML(response.body[/id="#{link_id}" href="([^"]*)"/, 1])
        expect(href).to include("q=101", "room_status=dirty", "date=2026-07-21")
      end
    end

    # The export is a list of tasks, headed by a count of them, so a room with
    # nothing to do is not a line in it -- and a checkout task is named there the
    # way the board names it rather than by its own raw status.
    it "exports the tasks only, under the same status the board shows" do
      booking = create(:booking, hotel: hotel, status: "checkout_required")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning",
             requested_at: Time.current, metadata: { "room_number" => "101" })

      get hotel_housekeeping_tasks_path(hotel, format: :csv)

      expect(response.body).to include("Checkout Room Cleaning,New")
      expect(response.body).not_to include("Pending")
      expect(response.body).not_to include("No Task")
      expect(response.body.lines.size).to eq(2) # the header, and the one real task
    end

    it "does not expose the removed legacy xls format" do
      expect(Mime::Type.lookup_by_extension(:xls)).to be_nil

      get hotel_housekeeping_tasks_path(hotel, format: :xls)

      expect(response).to have_http_status(:not_acceptable)
    end
  end

  describe "board access under the split housekeeping permissions" do
    def regrant(*slugs)
      role.role_permissions.destroy_all
      slugs.each do |slug|
        permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
        RolePermission.create!(role: role, permission: permission)
      end
    end

    it "admits a perform-only user, who is the housekeeper doing the work" do
      regrant("perform_housekeeping_tasks")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to have_http_status(:ok)
    end

    it "admits a dispatch-only user, who assigns the work" do
      regrant("dispatch_housekeeping_tasks")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to have_http_status(:ok)
    end

    it "turns away a user holding neither half" do
      regrant("manage_requests")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end
  end

  describe "the board's controls" do
    def regrant(*slugs)
      role.role_permissions.destroy_all
      slugs.each do |slug|
        permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
        RolePermission.create!(role: role, permission: permission)
      end
    end

    def board_with_task(details: "Clean the sheets", status: "in_progress", metadata: {})
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(
        :housekeeping_request,
        booking: booking,
        request_details: details,
        status: status,
        room_number: "101",
        metadata: metadata
      )
    end

    it "hands every selection control to a styled component rather than a bare select" do
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      selects = response.body.scan(/<select[^>]*>/)
      expect(selects).to be_present
      expect(selects).to all(match(/panel-select-menu__native|panel-combobox__native/))
    end

    it "scrolls the board in its own box, under a header that stays put" do
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("max-h-[75dvh] overflow-y-auto overscroll-none")
      expect(response.body).to include('data-sticky-header="true"')
    end

    it "gives the board's own controls unique ids" do
      board_with_task
      board_with_task(details: "Restock minibar")

      get hotel_housekeeping_tasks_path(hotel)

      board_ids = response.body.scan(/\sid="(hk-[^"]+)"/).flatten
      expect(board_ids).to be_present
      expect(board_ids).to eq(board_ids.uniq)
    end

    it "spans a room's columns across its tasks so the task columns line up" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Sheets", status: "in_progress", room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Towels", status: "in_progress", room_number: "101")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include('rowspan="2"')
    end

    it "makes the room-type group a keyboard-operable button" do
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include('aria-expanded="true"')
      expect(response.body).to include("data-table-group-group-param")
    end

    it "offers one status button, carrying the task's next step only" do
      board_with_task(status: "pending", metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Start cleaning #{room_type.name} 101")
      expect(response.body).not_to include("Complete #{room_type.name} 101")
    end

    it "makes the status button itself explain why it is dead while nobody holds the task" do
      board_with_task(status: "pending")

      get hotel_housekeeping_tasks_path(hotel)

      button = response.body[/<button[^>]*aria-label="Start cleaning[^>]*>/]
      # aria-disabled, not disabled: a disabled button takes neither hover nor focus,
      # so it could never open its own explanation.
      expect(button).to include('aria-disabled="true"')
      expect(button).to include("popover__trigger")
      expect(response.body).to include("Assign a housekeeper in the Assign to column first")
      # No separate help icon beside the button.
      expect(response.body).not_to include("Why this task cannot be started")
    end

    it "drops the explanation and lets the button submit once the task is held" do
      board_with_task(status: "pending", metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      button = response.body[/<button[^>]*aria-label="Start cleaning[^>]*>/]
      expect(button).to include('type="submit"')
      expect(button).not_to include("popover__trigger")
      expect(response.body).not_to include("Assign a housekeeper in the Assign to column first")
    end

    it "opens the start button once the task has an assignee" do
      board_with_task(status: "pending", metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body[/<button[^>]*aria-label="Start cleaning[^>]*>/]).not_to include("disabled")
    end

    it "swaps the start button for Complete once the task is under way" do
      board_with_task(status: "in_progress", metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Complete #{room_type.name} 101")
      expect(response.body).not_to include("Start cleaning")
    end

    it "holds the complete button shut until the room is being cleaned" do
      board_with_task(metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body[/<button[^>]*aria-label="Complete [^>]*>/]).to include("disabled")
    end

    it "opens the complete button once the room is being cleaned" do
      board_with_task(metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "cleaning")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body[/<button[^>]*aria-label="Complete [^>]*>/]).not_to include("disabled")
    end

    it "puts a long task note behind a hover popover, reachable without a mouse" do
      long_note = "Guest spilled coffee across both beds and the rug, needs a full change of linen plus a deep vacuum before the next arrival"
      board_with_task(details: long_note)

      get hotel_housekeeping_tasks_path(hotel)

      note_cell = response.body[/<td class="max-w-xs">.*?<\/td>/m]
      expect(note_cell).to include("popover-root")
      expect(note_cell).to include("line-clamp-2")
      # A real <button> trigger, so hover is not the only way in.
      expect(note_cell).to include("popover__trigger")
      expect(note_cell).to include(long_note)
    end

    it "leaves a short task note alone" do
      board_with_task(details: "Towels")

      get hotel_housekeeping_tasks_path(hotel)

      note_cell = response.body[/<td class="max-w-xs">.*?<\/td>/m]
      expect(note_cell).to include("Towels")
      expect(note_cell).not_to include("popover-root")
      expect(note_cell).not_to include("line-clamp-2")
    end

    it "consolidates arrival and departure into one column each" do
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("<th scope=\"col\" class=\"text-end\">Arrival</th>")
      expect(response.body).to include("<th scope=\"col\" class=\"text-end\">Departure</th>")
      expect(response.body).not_to include("Arrival time")
    end

    it "puts assign to before room status, and room status before task status" do
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      header = response.body[/<thead>.*?<\/thead>/m]
      expect(header.index("Assign to")).to be < header.index("Room status")
      expect(header.index("Room status")).to be < header.index("Task status")
    end

    it "offers a dispatcher a searchable staff combobox on the task" do
      regrant("dispatch_housekeeping_tasks", "manage_requests")
      staff = create(:user, account: account, name: "Siti Aminah")
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Assign task for #{room_type.name} 101")
      expect(response.body).to include("panel-combobox")
      expect(response.body).to include("Siti Aminah")
      expect(response.body).not_to include("Take task for")
    end

    it "keeps Unassigned pickable in the combobox and commits the pick straight away" do
      regrant("dispatch_housekeeping_tasks", "manage_requests")
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      assign_cell = response.body[/<form[^>]*#{Regexp.escape(assign_hotel_housekeeping_task_path(hotel, HousekeepingRequest.last))}.*?<\/form>/m]
      expect(assign_cell).to include("data-panels-ui--combobox-allow-empty-option-value=\"true\"")
      expect(assign_cell).to include(">Unassigned</option>")
      expect(assign_cell).to include("change-&gt;auto-submit#submitNow")
    end

    it "offers a housekeeper a take button on unclaimed work" do
      regrant("perform_housekeeping_tasks", "manage_requests")
      board_with_task

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Take task for #{room_type.name} 101")
      expect(response.body).not_to include("Assign task for")
    end

    it "offers a housekeeper a release button on work they hold" do
      regrant("perform_housekeeping_tasks", "manage_requests")
      board_with_task(metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Release task for #{room_type.name} 101")
      expect(response.body).not_to include("Take task for")
    end

    it "offers a housekeeper nothing on a colleague's work" do
      regrant("perform_housekeeping_tasks", "manage_requests")
      colleague = create(:user, account: account, name: "Siti Aminah")
      board_with_task(metadata: { "assigned_to" => colleague.id, "assigned_to_name" => colleague.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Siti Aminah")
      expect(response.body).not_to include("Take task for")
      expect(response.body).not_to include("Release task for")
    end
  end

  describe "PATCH /hotel/:hotel_id/housekeeping_tasks/:id/assign" do
    it "assigns a staff member to the request metadata" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch assign_hotel_housekeeping_task_path(hotel, req), params: { assigned_to: staff.id }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(req.reload.metadata["assigned_to"]).to eq(staff.id)
      expect(req.reload.metadata["assigned_to_name"]).to eq(staff.name)
      expect(req.reload.metadata["assignment_history"]).to be_present
    end

    it "returns to the board the user was actually looking at" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)

      patch assign_hotel_housekeeping_task_path(hotel, req), params: {
        assigned_to: staff.id,
        filters: { q: "101", date: "2026-07-30", room_status: "dirty", assigned_to: staff.id.to_s }
      }

      expect(response).to redirect_to(
        hotel_housekeeping_tasks_path(hotel, q: "101", date: "2026-07-30", room_status: "dirty", assigned_to: staff.id.to_s)
      )
    end

    it "ignores anything outside the board's own filters" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)

      patch assign_hotel_housekeeping_task_path(hotel, req), params: {
        assigned_to: staff.id,
        filters: { q: "101", host: "evil.example.com", script: "<script>" }
      }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel, q: "101"))
    end

    it "leaves the assignment history intact" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch assign_hotel_housekeeping_task_path(hotel, req), params: { assigned_to: staff.id }

      history_entry = req.reload.metadata["assignment_history"].last
      expect(history_entry["assigned_to_id"]).to eq(staff.id)
      expect(history_entry["assigned_to_name"]).to eq(staff.name)
      expect(history_entry["assigned_by_id"]).to eq(user.id)
      expect(history_entry["assigned_by_name"]).to eq(user.name)
      expect(history_entry["timestamp"]).to be_present
    end
  end

  describe "checkout room cleaning rows" do
    it "shows checkout requests with their own assign and status routes" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:check_out_request, booking: booking, status: "assigned", guest_notes: "Checkout Room Cleaning",
             metadata: { "room_number" => "101", "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Checkout Room Cleaning")
      expect(response.body).to include(hotel_assign_checkout_request_path(hotel, booking.check_out_requests.first))
      expect(response.body).to include(hotel_checkout_request_status_path(hotel, booking.check_out_requests.first))
      expect(response.body).to include("Start cleaning #{room_type.name} 101")
    end

    it "assigns checkout requests and advances the workflow status" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      request = create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch hotel_assign_checkout_request_path(hotel, request), params: { assigned_to: staff.id }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(request.reload.status).to eq("assigned")
      expect(request.metadata["assigned_to"]).to eq(staff.id)
      expect(request.metadata["assigned_to_name"]).to eq(staff.name)
      expect(request.metadata["workflow_status"]).to eq("assigned")
    end

    it "assigns every active room task together and records the collective audit event" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      checkout_request = create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })
      housekeeping_request = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch hotel_assign_checkout_request_path(hotel, checkout_request), params: { assigned_to: staff.id }

      expect(checkout_request.reload.metadata).to include("assigned_to" => staff.id, "assigned_to_name" => staff.name)
      expect(housekeeping_request.reload.metadata).to include("assigned_to" => staff.id, "assigned_to_name" => staff.name)
      audit = RoomOperationalAuditLog.find_by!(hotel: hotel, event_type: "housekeeping_assignment_changed")
      expect(audit).to have_attributes(room_number: "101", user: user)
      expect(audit.metadata["tasks"]).to contain_exactly(
        { "type" => "CheckOutRequest", "id" => checkout_request.id },
        { "type" => "HousekeepingRequest", "id" => housekeeping_request.id }
      )
    end

    it "returns to the board the user was looking at, exactly as a housekeeping assignment does" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      request = create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch hotel_assign_checkout_request_path(hotel, request), params: {
        assigned_to: staff.id,
        filters: { q: "101", date: "2026-07-30", room_status: "dirty", host: "evil.example.com" }
      }

      expect(response).to redirect_to(
        hotel_housekeeping_tasks_path(hotel, q: "101", date: "2026-07-30", room_status: "dirty")
      )
    end

    it "updates checkout requests through the checkout status route" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      request = create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })

      patch hotel_checkout_request_status_path(hotel, request), params: { status: "in_progress" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(request.reload.status).to eq("in_progress")
      expect(request.metadata["workflow_status"]).to eq("in_progress")
    end
  end

  describe "PATCH /hotel/:hotel_id/housekeeping_tasks/:id/status" do
    it "completes the housekeeping request, causing it to disappear and fallback to No Task" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101", request_details: "Clean the window")

      # Verify it's displayed initially
      get hotel_housekeeping_tasks_path(hotel)
      expect(response.body).to include("Clean the window")

      # Update status to completed
      patch status_hotel_housekeeping_task_path(hotel, req), params: { status: "completed" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(req.reload.status).to eq("completed")

      # Loading the tasks page again should not show the request, and should display No Task
      get hotel_housekeeping_tasks_path(hotel)
      expect(response.body).not_to include("Clean the window")
      expect(response.body).to include("No Task")
    end

    it "returns to the board the caller came from" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      board = hotel_housekeeping_tasks_path(hotel, q: "101")

      patch status_hotel_housekeeping_task_path(hotel, req),
            params: { status: "completed", redirect_to: board }

      expect(response).to redirect_to(board)
    end

    it "falls back rather than failing when redirect_to points off this app" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")

      [ "https://evil.example.com/steal", "//evil.example.com", "javascript:alert(1)" ].each do |crafted|
        patch status_hotel_housekeeping_task_path(hotel, req),
              params: { status: "completed", redirect_to: crafted }

        expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      end
    end

    # The board admits a perform-only housekeeper, so the button it hands them
    # has to be a button they may actually press. It used to post to the
    # Requests page's route, which asks for managing requests instead.
    it "is open to the perform-only housekeeper the board is built for" do
      role.role_permissions.destroy_all
      perform = Permission.find_or_create_by!(slug: "perform_housekeeping_tasks") { |record| record.name = "Perform Housekeeping Tasks" }
      RolePermission.create!(role: role, permission: perform)
      booking = create(:booking, hotel: hotel, status: "checked_in")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "assigned", room_number: "101",
                                          metadata: { "assigned_to" => user.id, "assigned_to_name" => user.name })

      get hotel_housekeeping_tasks_path(hotel)
      expect(response.body).to include(status_hotel_housekeeping_task_path(hotel, req))

      patch status_hotel_housekeeping_task_path(hotel, req), params: { status: "in_progress" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(req.reload.status).to eq("in_progress")
    end
  end
end
