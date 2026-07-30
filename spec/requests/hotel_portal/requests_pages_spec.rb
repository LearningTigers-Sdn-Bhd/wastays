require "rails_helper"

RSpec.describe "Hotel portal request pages", type: :request do
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
    expect(response.body).to include(hotel_archive_request_path(hotel, kind: "checkout", request_id: checkout.id))
  end

  it "can archive completed checkout requests" do
    booking = create(:booking, hotel: hotel, guest_name: "John completed")
    checkout = create(:check_out_request, booking: booking, status: "completed", guest_notes: "Clean up completed")

    patch hotel_archive_request_path(hotel, kind: "checkout", request_id: checkout.id)

    expect(response).to redirect_to(hotel_requests_path(hotel))
    expect(checkout.reload.metadata["archived_at"]).to be_present
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
