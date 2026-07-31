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
    expect(response.body).to include("Requests Board")
    expect(response.body).to include("Fresh towels")
    expect(response.body).not_to include("onclick=")
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

    # Reorderable is not the same as somewhere a card may be put: Checkout takes
    # no cards, and moving it along the board must not change that.
    it "still refuses a card dropped in the checkout lane" do
      get hotel_requests_path(hotel)
      lane = Nokogiri::HTML(response.body).at_css('[data-board-column="checkout"]')

      expect(lane["data-move-url"]).to be_nil
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

  it "renders the archive page with archived requests and no inline handlers" do
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

    get hotel_request_archive_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Request Archive")
    expect(response.body).to include("Air conditioner noisy")
    expect(response.body).not_to include("onclick=")
    # Internal notes belong to the detail sheet now, not to every row of the table.
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
      expect(response.body).to include(%(target="requests_count_archived"))
      expect(response.body).to include(%(target="requests_count_completed"))
      expect(request.reload.archived_at).to be_present
    end

    it "says why when the lane will not take the card" do
      patch hotel_requests_move_path(hotel, to: "checkout"),
            params: { kind: "housekeeping", request_id: request.id },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("requests_board_flash")
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

  # The archive is read a page at a time by naming the last row read, not by
  # counting rows that staff are still archiving and restoring underneath it.
  describe "reading the archive past its first page" do
    let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisyah") }

    before do
      (HotelPortal::Requests::Paging::PAGE_SIZE + 3).times do |index|
        create(:complaint_request, booking: booking, status: "resolved",
               complaint_details: "Filed #{index}", archived_at: (index + 1).minutes.ago)
      end
    end

    def archive_row_ids
      Nokogiri::HTML(response.body).css("tbody tr").map do |row|
        row.at_css("a[data-turbo-frame='requests_action_sheet']")["href"][/\d+\z/]
      end
    end

    it "says how much archive there is and offers the rest of it" do
      get hotel_request_archive_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("#{HotelPortal::Requests::Paging::PAGE_SIZE + 3} archived requests in this range")
      expect(response.body).to include("Older")
      # Nothing behind the newest page to go back to.
      expect(response.body).not_to include("Newest")
    end

    it "shows each archived request once across the two pages" do
      get hotel_request_archive_path(hotel)
      first_ids = archive_row_ids
      older = Nokogiri::HTML(response.body).css("a").find { |link| link.text.include?("Older") }

      get older["href"]
      second_ids = archive_row_ids

      expect(response).to have_http_status(:ok)
      expect(first_ids.size).to eq(HotelPortal::Requests::Paging::PAGE_SIZE)
      expect(second_ids.size).to eq(3)
      expect(first_ids & second_ids).to be_empty
    end

    it "offers a way back to the newest page, and nothing older beyond the last" do
      get hotel_request_archive_path(hotel)
      older = Nokogiri::HTML(response.body).css("a").find { |link| link.text.include?("Older") }

      get older["href"]

      expect(response.body).to include("Newest")
      expect(response.body).not_to include(">Older")
    end

    it "carries the filters into the rest of the archive" do
      get hotel_request_archive_path(hotel, kind: "complaint")
      older = Nokogiri::HTML(response.body).css("a").find { |link| link.text.include?("Older") }

      expect(older["href"]).to include("kind=complaint")
      expect(older["href"]).to include("cursor=")
    end

    # A cursor from one window is not a place another one has, so moving the
    # range starts the archive again rather than carrying where it got to.
    it "starts the archive again when the range moves" do
      hotel_today = Time.current.in_time_zone(hotel.hotel_time_zone).to_date

      get hotel_request_archive_path(hotel)
      older = Nokogiri::HTML(response.body).css("a").find { |link| link.text.include?("Older") }

      get older["href"]

      step_back = hotel_request_archive_path(hotel, date: (hotel_today - 7).iso8601, days: 7)
      expect(response.body).to include(ERB::Util.html_escape(step_back))
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

    it "carries the range through the archive's own filters" do
      get hotel_request_archive_path(hotel, kind: "housekeeping", days: 14)

      expect(response.body).to include(link_to_path(hotel_request_archive_path(hotel, kind: "housekeeping", date: (hotel_today - 14).iso8601, days: 14)))
    end

    it "offers a way back to today only when it is looking elsewhere" do
      today_window = link_to_path(hotel_requests_path(hotel, date: hotel_today.iso8601, days: 7))

      get hotel_requests_path(hotel, date: 20.days.ago.to_date.iso8601)
      expect(response.body).to include(today_window)

      get hotel_requests_path(hotel)
      expect(response.body).not_to include(today_window)
    end

    it "says how much outstanding work the range is leaving out" do
      create(:housekeeping_request, booking: booking, status: "pending",
             request_details: "Stale towels", requested_at: 20.days.ago)

      get hotel_requests_path(hotel)

      expect(response.body).to include("1 older request outside this range")
      expect(response.body).to include(link_to_path(hotel_requests_path(hotel, date: hotel_today.iso8601, days: 30)))
    end

    it "says nothing about older work when the range already reaches it" do
      create(:housekeeping_request, booking: booking, status: "pending",
             request_details: "Stale towels", requested_at: 20.days.ago)

      get hotel_requests_path(hotel, days: 30)

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
