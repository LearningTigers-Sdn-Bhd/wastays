require "rails_helper"

RSpec.describe "Hotel portal request pages", type: :request do
  def dom_id_for(record)
    kind = record.is_a?(ComplaintRequest) ? "complaint" : "housekeeping"
    "request_#{kind}_#{record.id}"
  end

  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_requests") { |record| record.name = "Manage Requests" } }

  before do
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  it "renders the requests board" do
    booking = create(:booking, hotel: hotel, guest_name: "Aisyah", confirmation_token: "WS-REQ123")
    create(
      :housekeeping_request,
      booking: booking,
      request_details: "Fresh towels",
      metadata: { "source" => "concierge_page" }
    )

    get hotel_requests_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Housekeeping")
    expect(response.body).to include("Fresh towels")
    expect(response.body).not_to include("onclick=")
  end

  it "groups the toolbar controls in a two-row card with an edge-to-edge divider" do
    get hotel_requests_path(hotel)

    document = Nokogiri::HTML(response.body)
    toolbar = document.at_css('[data-slot="requests-toolbar"]')
    form = toolbar.at_css("form")
    context = document.at_css('[data-slot="requests-toolbar-context"]')

    expect(toolbar["class"].split).to include("overflow-hidden", "rounded-lg", "border", "border-border", "bg-card")
    expect(form["class"].split).to include("divide-y", "divide-border")
    expect(form["method"]).to eq("get")
    expect(form["data-turbo-frame"]).to be_nil
    expect(form.element_children.map { |row| row["data-slot"] }).to eq(
      %w[requests-toolbar-controls requests-toolbar-lanes]
    )
    expect(toolbar.at_css('[data-slot="requests-toolbar-context"]')).to be_nil
    expect(context).to be_present
    expect(context["class"].split).not_to include("border-t")
  end

  it "labels search and renders outlined lane toggles with badge counts" do
    get hotel_requests_path(hotel)

    document = Nokogiri::HTML(response.body)
    toolbar = document.at_css('[data-slot="requests-toolbar"]')
    search_label = toolbar.at_css("label[for='q']")
    toggle_group = toolbar.at_css('[data-slot="toggle-group"]')
    toggle_items = toggle_group.css('[data-slot="toggle-group-item"]')

    expect(search_label.text.squish).to eq("Search")
    expect(search_label["class"].split).not_to include("sr-only")
    expect(toggle_group["data-variant"]).to eq("outline")
    expect(toggle_items).not_to be_empty
    expect(toggle_items).to all(satisfy do |item|
      item["data-variant"] == "outline" &&
        item.at_css(".panel-badge-rounded[data-variant='neutral'][data-size='sm']").present?
    end)
  end

  it "renders neutral lanes and restrained request cards with semantic badges" do
    booking = create(:booking, hotel: hotel, guest_name: "Aisyah")
    request = create(
      :housekeeping_request,
      booking: booking,
      status: "pending",
      request_details: "Fresh towels"
    )

    get hotel_requests_path(hotel)

    document = Nokogiri::HTML(response.body)
    lanes = document.css("[data-board-column]")
    card = document.at_css("##{dom_id_for(request)}")

    expect(lanes).not_to be_empty
    lanes.each do |lane|
      expect(lane["class"].split).to include("rounded-lg", "border", "border-border", "bg-card")
      expect(lane["class"].split).not_to include("rounded-2xl", "border-t-4")
      expect(lane.at_css("#requests_count_#{lane['data-board-column']}")).to be_nil
    end

    expect(card["class"].split).to include("rounded-lg", "border", "border-border", "bg-card")
    expect(card["class"].split).not_to include("rounded-xl", "shadow-sm")
    expect(card.css(".panel-badge-rounded").size).to eq(2)

    lane_classes = lanes.css("[class]").map { |element| element["class"] }.join(" ")
    expect(lane_classes).not_to match(/\b(?:blue|rose|amber|green|slate|emerald)-/)
    expect(lane_classes).not_to include("font-black", "uppercase")
  end

  it "gives each lane a restrained semantic header tone" do
    get hotel_requests_path(hotel)

    lanes = Nokogiri::HTML(response.body).css("[data-board-column]").index_by { |lane| lane["data-board-column"] }
    expected_tones = {
      "housekeeping" => %w[bg-info/10 bg-info],
      "complaint" => %w[bg-destructive/10 bg-destructive],
      "checkout" => %w[bg-warning/10 bg-warning],
      "completed" => %w[bg-success/10 bg-success],
      "archived" => %w[bg-muted bg-muted-foreground]
    }

    expected_tones.each do |key, (header_class, marker_class)|
      lane = lanes.fetch(key)
      header = lane.element_children.first
      marker = header.at_css('[data-slot="requests-lane-marker"]')

      expect(header["class"].split).to include(header_class)
      expect(marker["class"].split).to include(marker_class)
      expect(marker["aria-hidden"]).to eq("true")
    end
  end

  it "gives the board a fixed dynamic viewport height with bottom breathing room" do
    get hotel_requests_path(hotel)

    document = Nokogiri::HTML(response.body)
    page = document.at_css(".panel-page")
    results = document.at_css("turbo-frame#requests_board_results")
    scroller = results.at_css(".panel-scroll-area")
    page_scroller = page.parent

    expect(page["class"].split).not_to include("panel-page--workspace")
    expect(page_scroller["class"].split).to include("overscroll-none")
    expect(page_scroller["class"].split).not_to include("overscroll-contain")
    expect(results["class"]).to be_blank
    expect(scroller["class"].split).to include("h-[72dvh]", "pb-4")
    expect(scroller.at_css(".panel-scroll-area__viewport")["class"].split).not_to include("overscroll-none")

    document.css("[data-board-column]").each do |lane|
      lane_body = lane.at_css(".overflow-y-auto")

      expect(lane["class"].split).to include("xl:h-full")
      expect(lane_body["class"].split).to include("min-h-0", "flex-1", "overflow-y-auto")
      expect(lane_body["class"].split).not_to include("overscroll-none")
    end
  end

  # The archive is a column of the board, not only a page of its own.
  describe "the archive column" do
    let(:booking) { create(:booking, hotel: hotel, guest_name: "Suri") }

    let!(:archived) do
      create(:housekeeping_request, booking: booking, status: "completed",
             request_details: "Filed towels", completed_at: Time.current, archived_at: Time.current)
    end

    it "shows what has been put away alongside the working columns" do
      get hotel_requests_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Archived")
      expect(response.body).to include("Filed towels")
    end

    it "offers the way back out of the archive, through the same endpoint a drag uses" do
      get hotel_requests_path(hotel)
      card = Nokogiri::HTML(response.body).at_css("article##{dom_id_for(archived)}")

      expect(card).to be_present
      expect(card.text).to include("Restore")
      expect(card.at_css("form")["action"]).to eq(hotel_requests_move_path(hotel, to: "completed"))
    end

    # Restoring is a move out of the archive, so the card can be dragged back to
    # a lane as well as sent there by its button.
    it "lets an archived card be carried back out" do
      get hotel_requests_path(hotel)
      card = Nokogiri::HTML(response.body).at_css("article##{dom_id_for(archived)}")

      expect(card["draggable"]).to eq("true")
      expect(card["tabindex"]).to eq("0")
    end

    it "reads the rest of the column the way every other column is read" do
      get hotel_requests_column_path(hotel, "archived")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Filed towels")
    end

    # The order the board opens in. Somebody who drags a lane elsewhere keeps
    # their own; this is where everyone else starts.
    it "shows the lanes in their working order" do
      get hotel_requests_path(hotel)

      order = Nokogiri::HTML(response.body).css("[data-board-column]").map { |lane| lane["data-board-column"] }

      expect(order).to eq(%w[housekeeping complaint checkout completed archived])
    end

    # Every lane can be dragged along the board, including the two that take no
    # cards: where a lane sits is the operator's business, and a lane being
    # read-only for cards says nothing about where they want to read it.
    it "lets every lane be reordered" do
      get hotel_requests_path(hotel)
      document = Nokogiri::HTML(response.body)

      handles = document.css('[data-action*="requests-board#columnDragStart"]')
      expect(handles.size).to eq(HotelPortal::Requests::Column.all.size)

      document.css("[data-board-column]").each do |lane|
        expect(lane["data-action"]).to include("requests-board#drop"),
          "the #{lane['data-board-column']} lane cannot receive a dragged lane"
      end
    end

    # Checkout still receives the drop event so the server can explain the
    # refusal, but its empty acceptance list lets the board mark it unavailable
    # before the card is released.
    it "marks checkout unavailable while still giving invalid drops an alert path" do
      get hotel_requests_path(hotel)
      lane = Nokogiri::HTML(response.body).at_css('[data-board-column="checkout"]')

      expect(lane["data-accepted-request-kinds"]).to be_blank
      expect(lane["data-move-url"]).to eq(hotel_requests_move_path(hotel, to: "checkout"))
      expect(lane.at_css("[data-requests-board-drop-hint]")).to be_present
      expect(lane.at_css("[data-requests-board-drop-hint]")["hidden"]).to eq("hidden")
    end

    it "exposes the server transition map so dragging can show valid destinations" do
      get hotel_requests_path(hotel)
      lanes = Nokogiri::HTML(response.body).css("[data-board-column]").index_by { |lane| lane["data-board-column"] }

      expect(lanes.fetch("housekeeping")["data-accepted-request-kinds"]).to eq("housekeeping")
      expect(lanes.fetch("complaint")["data-accepted-request-kinds"]).to eq("complaint")
      expect(lanes.fetch("completed")["data-accepted-request-kinds"].split).to contain_exactly(
        "housekeeping", "complaint", "checkout"
      )
      expect(lanes.fetch("archived")["data-accepted-request-kinds"]).to eq("*")
    end

    # Five columns are wider than the page, so the board scrolls sideways inside
    # its own viewport instead of making the page do it.
    it "scrolls the board sideways rather than the page" do
      get hotel_requests_path(hotel)

      scroller = Nokogiri::HTML(response.body).at_css(".panel-scroll-area")

      expect(scroller).to be_present
      expect(scroller["data-orientation"]).to eq("horizontal")
      expect(scroller.css('[data-board-column]').size).to eq(HotelPortal::RequestsBoard::COLUMNS.size)
    end
  end

  # Which lanes are on the board is the operator's to say, and a lane switched
  # off is a lane the board does not read at all.
  describe "choosing which lanes to show" do
    let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisyah") }

    before do
      create(:housekeeping_request, booking: booking, status: "pending", request_details: "Fresh towels")
      create(:complaint_request, booking: booking, status: "pending", complaint_details: "AC noisy")
    end

    it "shows every lane when none is asked for" do
      get hotel_requests_path(hotel)

      order = Nokogiri::HTML(response.body).css("[data-board-column]").map { |lane| lane["data-board-column"] }

      expect(order).to eq(%w[housekeeping complaint checkout completed archived])
    end

    it "draws only the lanes asked for" do
      get hotel_requests_path(hotel, lanes: %w[housekeeping])

      document = Nokogiri::HTML(response.body)
      order = document.css("[data-board-column]").map { |lane| lane["data-board-column"] }

      expect(order).to eq(%w[housekeeping])
      expect(document.text).to include("Fresh towels")
      expect(document.text).not_to include("AC noisy")
    end

    it "draws several when several are asked for, in the board's own order" do
      get hotel_requests_path(hotel, lanes: %w[complaint housekeeping])

      order = Nokogiri::HTML(response.body).css("[data-board-column]").map { |lane| lane["data-board-column"] }

      expect(order).to eq(%w[housekeeping complaint])
    end

    # The control that switches a lane back on has to name it, and say how much
    # is waiting in it, whether or not it is being drawn.
    it "still names every lane, with its count, when one is showing" do
      get hotel_requests_path(hotel, lanes: %w[housekeeping])

      document = Nokogiri::HTML(response.body)
      toggles = document.css('[data-slot="toggle-group-item"]')

      expect(toggles.map { |item| item["data-value"] }).to eq(%w[all housekeeping complaint checkout completed archived])
      expect(document.at_css("#requests_lane_count_all").text.strip).to eq("2")
      expect(document.at_css("#requests_lane_count_complaint").text.strip).to eq("1")
    end

    it "marks All, rather than every individual lane, when the full board is showing" do
      get hotel_requests_path(hotel)

      toggles = Nokogiri::HTML(response.body).css('[data-slot="toggle-group-item"]')
      on = toggles.select { |item| item["data-state"] == "on" }.map { |item| item["data-value"] }

      expect(on).to eq(%w[all])
    end

    it "uses the All URL value to draw the full board" do
      get hotel_requests_path(hotel, lanes: %w[all])

      document = Nokogiri::HTML(response.body)
      order = document.css("[data-board-column]").map { |lane| lane["data-board-column"] }
      on = document.css('[data-slot="toggle-group-item"][data-state="on"]').map { |item| item["data-value"] }

      expect(order).to eq(%w[housekeeping complaint checkout completed archived])
      expect(on).to eq(%w[all])
    end

    it "marks the lanes that are on" do
      get hotel_requests_path(hotel, lanes: %w[housekeeping])

      toggles = Nokogiri::HTML(response.body).css('[data-slot="toggle-group-item"]')
      on = toggles.select { |item| item["data-state"] == "on" }.map { |item| item["data-value"] }

      expect(on).to eq(%w[housekeeping])
    end

    # An empty selection reaches the server as no parameter at all, so it cannot
    # be told apart from a board just opened.
    it "falls back to every lane when the selection is empty" do
      get hotel_requests_path(hotel, lanes: [])

      order = Nokogiri::HTML(response.body).css("[data-board-column]").map { |lane| lane["data-board-column"] }

      expect(order).to eq(%w[housekeeping complaint checkout completed archived])
    end

    it "ignores a lane it does not have" do
      get hotel_requests_path(hotel, lanes: %w[housekeeping nonsense])

      order = Nokogiri::HTML(response.body).css("[data-board-column]").map { |lane| lane["data-board-column"] }

      expect(order).to eq(%w[housekeeping])
    end

    # A lazy frame that dropped the selection would ask for a lane the board is
    # no longer reading.
    it "carries the selection into the rest of a lane" do
      (HotelPortal::Requests::Paging::PAGE_SIZE + 1).times do |index|
        create(:housekeeping_request, booking: booking, status: "pending", request_details: "Towels #{index}")
      end

      get hotel_requests_path(hotel, lanes: %w[housekeeping])

      frame = Nokogiri::HTML(response.body).css("turbo-frame[loading='lazy']").first

      expect(frame).to be_present
      expect(frame["src"]).to include("lanes")
    end
  end

  # The archive had a page of its own until it became a lane; what it used to
  # show is asked of the board now.
  it "shows archived requests on the board without inline handlers" do
    booking = create(:booking, hotel: hotel, guest_name: "Daniel", confirmation_token: "WS-ARC123")
    create(
      :complaint_request,
      booking: booking,
      complaint_details: "Air conditioner noisy",
      status: "resolved",
      completed_at: Time.current,
      archived_at: Time.current,
      internal_notes: [ { "body" => "Maintenance informed" } ]
    )

    get hotel_requests_column_path(hotel, "archived")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Air conditioner noisy")
    expect(response.body).not_to include("onclick=")
    # Internal notes belong to the detail sheet, not to every card.
    expect(response.body).not_to include("Maintenance informed")
  end

  it "renders completed checkout requests on the board with an archive button" do
    booking = create(:booking, hotel: hotel, guest_name: "John completed")
    checkout = create(:check_out_request, booking: booking, status: "completed", guest_notes: "Clean up completed")

    get hotel_requests_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Clean up completed")
    expect(response.body).to include(hotel_requests_move_path(hotel, to: "archived"))
  end

  it "can archive completed checkout requests" do
    booking = create(:booking, hotel: hotel, guest_name: "John completed")
    checkout = create(:check_out_request, booking: booking, status: "completed", guest_notes: "Clean up completed")

    patch hotel_archive_request_path(hotel, kind: "checkout", request_id: checkout.id)

    expect(response).to redirect_to(hotel_requests_path(hotel))
    expect(checkout.reload.metadata["archived_at"]).to be_present
  end

  # Moving a card always leaves one lane and joins another, so the answer has to
  # carry both -- a redirect could only ever refill the frame it was asked from.
  describe "moving a card" do
    let(:booking) { create(:booking, hotel: hotel, guest_name: "Sena") }
    let!(:request) do
      create(:housekeeping_request, booking: booking, status: "completed",
             request_details: "Towels", completed_at: Time.current, archived_at: nil)
    end

    it "answers with both lanes and the card that moved" do
      patch hotel_requests_move_path(hotel, to: "archived"),
            params: { kind: "housekeeping", request_id: request.id },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="remove" target="#{dom_id_for(request)}"))
      expect(response.body).to include(%(target="requests_column_archived_start"))
      expect(response.body).to include(%(target="requests_count_label_archived"))
      expect(response.body).to include(%(target="requests_count_label_completed"))
      expect(response.body).to include(%(target="requests_lane_count_archived"))
      expect(response.body).to include(%(target="requests_lane_count_completed"))
      expect(request.reload.archived_at).to be_present
    end

    it "says why when the lane will not take the card" do
      patch hotel_requests_move_path(hotel, to: "checkout"),
            params: { kind: "housekeeping", request_id: request.id },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(%(target="toast-viewport"))
      expect(response.body).to include(%(data-controller="toast-trigger"))
      expect(response.body).to include("Request cannot be moved")
      expect(response.body).to include("cannot go there")
      expect(request.reload.archived_at).to be_nil
    end

    # The lanes sent back have to be the ones on screen, not an unfiltered board.
    it "reads the board back under the filters it was moved from" do
      patch hotel_requests_move_path(hotel, to: "archived", q: "nothing matches"),
            params: { kind: "housekeeping", request_id: request.id },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Towels")
    end
  end

  # A column reads itself as somebody scrolls it, so the placeholder that asks
  # for the next page has to be laid out like the page that replaces it: Turbo
  # swaps a frame's children and leaves its attributes where they are.
  describe "reading a column past its first page" do
    let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisyah") }

    before do
      (HotelPortal::RequestsBoard::PAGE_SIZE + 3).times do |index|
        create(:complaint_request, booking: booking, status: "pending", complaint_details: "Issue #{index}")
      end
    end

    it "leaves a lazy placeholder asking for the rest" do
      get hotel_requests_path(hotel)
      document = Nokogiri::HTML(response.body)

      placeholder = document.css('turbo-frame[loading="lazy"][id^="requests_column_complaint_"]').first

      expect(placeholder).to be_present
      expect(placeholder["src"]).to be_present
      expect(placeholder["class"]).to include("gap-3")
    end

    it "answers the placeholder with the rest of the column, spaced the same way" do
      get hotel_requests_path(hotel)
      placeholder = Nokogiri::HTML(response.body).css('turbo-frame[loading="lazy"][id^="requests_column_complaint_"]').first

      get placeholder["src"], headers: { "Turbo-Frame" => placeholder["id"] }
      document = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(document.css("turbo-frame##{placeholder['id']}")).to be_present
      expect(document.css("article").size).to eq(3)
      # Nothing left to ask for, so no further placeholder.
      expect(document.css('turbo-frame[loading="lazy"]')).to be_empty
    end

    it "shows each request once across the two pages" do
      get hotel_requests_path(hotel)
      first_page = Nokogiri::HTML(response.body)
      first_ids = first_page.css('article[data-request-kind="complaint"]').map { |node| node["data-request-id"] }
      placeholder = first_page.css('turbo-frame[loading="lazy"][id^="requests_column_complaint_"]').first

      get placeholder["src"], headers: { "Turbo-Frame" => placeholder["id"] }
      second_ids = Nokogiri::HTML(response.body).css("article").map { |node| node["data-request-id"] }

      expect(first_ids.size).to eq(HotelPortal::RequestsBoard::PAGE_SIZE)
      expect(first_ids & second_ids).to be_empty
      expect((first_ids + second_ids).uniq.size).to eq(HotelPortal::RequestsBoard::PAGE_SIZE + 3)
    end

    it "carries the search into the rest of the column" do
      get hotel_requests_path(hotel, q: "Aisyah")
      placeholder = Nokogiri::HTML(response.body).css('turbo-frame[loading="lazy"][id^="requests_column_complaint_"]').first

      expect(placeholder["src"]).to include("q=Aisyah")
    end

    it "refuses a column it does not have" do
      get hotel_requests_column_path(hotel, "minibar")

      expect(response).to redirect_to(hotel_requests_path(hotel))
    end
  end

  describe "the date range toolbar" do
    let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisyah") }

    # Query separators arrive in the markup escaped.
    def link_to_path(path)
      ERB::Util.html_escape(path)
    end

    # The window reckons in the hotel's zone, which need not be the app's.
    def hotel_today
      Time.current.in_time_zone(hotel.hotel_time_zone).to_date
    end

    it "offers every range and marks the one in use" do
      get hotel_requests_path(hotel, days: 14)

      expect(response).to have_http_status(:ok)
      HotelPortal::Requests::DateWindow::ALLOWED_DAYS.each do |days|
        expect(response.body).to include("Past #{days} days")
      end
    end

    it "carries the search through a step of the range" do
      get hotel_requests_path(hotel, q: "Aisyah", days: 7)

      expect(response.body).to include(link_to_path(hotel_requests_path(hotel, q: "Aisyah", date: (hotel_today - 7).iso8601, days: 7)))
    end

    it "carries a kind filter through a step of the range" do
      get hotel_requests_path(hotel, kind: "housekeeping", days: 5)

      expect(response.body).to include(link_to_path(hotel_requests_path(hotel, kind: "housekeeping", date: (hotel_today - 5).iso8601, days: 5)))
    end

    it "renders the toolbar from URL params and carries them through a date step" do
      get hotel_requests_path(
        hotel,
        q: "Aisyah",
        date: 3.days.ago.to_date.iso8601,
        days: 5,
        lanes: %w[housekeeping complaint]
      )

      document = Nokogiri::HTML(response.body)
      form = document.at_css('[data-slot="requests-toolbar"] form')
      selected_lanes = document.css('[data-slot="toggle-group-item"][data-state="on"]').map { |item| item["data-value"] }
      previous_date = 3.days.ago.to_date - 5

      expect(form.at_css("input[name='q']")["value"]).to eq("Aisyah")
      expect(form.at_css("input[name='date']")["value"]).to eq(3.days.ago.to_date.iso8601)
      expect(form.at_css("select[name='days'] option[selected]")["value"]).to eq("5")
      expect(selected_lanes).to eq(%w[housekeeping complaint])
      expect(response.body).to include(
        link_to_path(
          hotel_requests_path(
            hotel,
            q: "Aisyah",
            date: previous_date.iso8601,
            days: 5,
            lanes: %w[housekeeping complaint]
          )
        )
      )
    end

    it "offers a way back to today only when it is looking elsewhere" do
      today_window = link_to_path(hotel_requests_path(hotel, date: hotel_today.iso8601, days: 7))

      get hotel_requests_path(hotel, date: 20.days.ago.to_date.iso8601)
      expect(response.body).to include(today_window)

      get hotel_requests_path(hotel)
      expect(response.body).not_to include(today_window)
    end

    # The range governs what has been finished. Outstanding work is not reachable
    # by widening a range, so it is never behind one.
    it "shows outstanding work the range does not reach, on the narrowest range" do
      create(:housekeeping_request, booking: booking, status: "pending",
             request_details: "Stale towels", requested_at: 20.days.ago)

      get hotel_requests_path(hotel, days: 1)

      expect(response.body).to include("Stale towels")
      expect(response.body).not_to include("outside this range")
    end
  end

  # The housekeeping board only lets a performer advance work they hold. This
  # board reaches the same records, so it must not be the way around that.
  describe "advancing work held by somebody else" do
    let(:booking) { create(:booking, hotel: hotel) }
    let(:colleague) { create(:user, account: account) }

    def grant(slug)
      RolePermission.find_or_create_by!(
        role: role,
        permission: Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.titleize }
      )
    end

    it "refuses a performer advancing a housekeeping request assigned to a colleague" do
      grant("perform_housekeeping_tasks")
      request = create(
        :housekeeping_request,
        booking: booking,
        status: "assigned",
        metadata: { "assigned_to" => colleague.id }
      )

      patch hotel_request_status_path(hotel, kind: "housekeeping", request_id: request.id), params: { status: "completed" }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/not authorized/i)
      expect(request.reload.status).to eq("assigned")
    end

    it "refuses a performer advancing a checkout request assigned to a colleague" do
      grant("perform_housekeeping_tasks")
      checkout = create(
        :check_out_request,
        booking: booking,
        status: "assigned",
        metadata: { "assigned_to" => colleague.id }
      )

      patch hotel_request_status_path(hotel, kind: "checkout", request_id: checkout.id), params: { status: "completed" }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/not authorized/i)
      expect(checkout.reload.status).to eq("assigned")
    end

    it "lets a dispatcher advance a request assigned to somebody else" do
      grant("dispatch_housekeeping_tasks")
      request = create(
        :housekeeping_request,
        booking: booking,
        status: "assigned",
        metadata: { "assigned_to" => colleague.id }
      )

      patch hotel_request_status_path(hotel, kind: "housekeeping", request_id: request.id), params: { status: "completed" }

      expect(response).to redirect_to(hotel_requests_path(hotel))
      expect(request.reload.status).to eq("completed")
    end

    it "lets anybody resolve a complaint, which nobody holds" do
      complaint = create(:complaint_request, booking: booking, status: "pending")

      patch hotel_request_status_path(hotel, kind: "complaint", request_id: complaint.id), params: { status: "resolved" }

      expect(response).to redirect_to(hotel_requests_path(hotel))
      expect(complaint.reload.status).to eq("resolved")
    end
  end
end
