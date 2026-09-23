# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin reservation imports", type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, name: "eZee Import") }
  let(:superadmin) { create(:user, :superadmin, account: account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }

  let(:fixture) { Rails.root.join("spec/fixtures/files/ezee_reservation_list_sample.xls") }

  # The preview creates the ReservationImport row; committing enqueues the job
  # that fills it in.
  def latest_import = ReservationImport.recent_first.first
  let(:upload) do
    Rack::Test::UploadedFile.new(fixture, "application/vnd.ms-excel", original_filename: "Reservation List.xls")
  end

  # The fixture carries the property's real inventory, and the importer refuses a
  # row whose room category does not exist. Only the two categories the
  # assertions below touch are set up, so the rest land as blocked -- which is
  # itself worth asserting.
  before do
    sign_in_as(superadmin)
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "DLX", room_number_mode: "custom", quantity: 4, base_price: 305.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[A1 A2 A3 A4] }
    )
  end

  it "renders the upload form" do
    get new_admin_hotel_reservation_import_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reservation list export")
  end

  it "previews the file without creating anything" do
    expect {
      post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
      follow_redirect!
    }.not_to change(Booking, :count)

    expect(response.body).to include("Review this import")
    # Every category the fixture uses beyond DLX is missing here, so those rows
    # have to be reported rather than quietly dropped.
    expect(response.body).to include("No room category named")
  end

  it "refuses a file that is not a reservation list" do
    not_a_report = Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg"
    )

    # The file is read at upload now, so an unreadable one is refused by the
    # POST itself rather than by the page it would have redirected to.
    post admin_hotel_reservation_imports_path(hotel), params: { file: not_a_report }

    expect(response).to redirect_to(new_admin_hotel_reservation_import_path(hotel))
    expect(flash[:alert]).to be_present
    expect(ReservationImport.count).to be_zero
  end

  it "redirects the upload rather than rendering it, so Turbo accepts the form" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }

    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(admin_hotel_reservation_import_path(hotel, latest_import))
  end

  it "runs the import in the background and tracks its progress" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import

    expect {
      post commit_admin_hotel_reservation_import_path(hotel, import)
    }.to have_enqueued_job(Ezee::RunReservationImportJob).with(import.id)

    expect(response).to redirect_to(admin_hotel_reservation_import_path(hotel, import))
    expect(import.reload.status).to eq("queued")

    perform_enqueued_jobs

    import.reload
    expect(import.status).to eq("completed")
    expect(import.created_count).to be_positive
    expect(import.percent_complete).to eq(100)
    expect(import.processed_rows).to eq(import.total_rows)

    booking = hotel.bookings.where.not(external_reference: nil).first
    expect(booking.external_reference).to be_present
    # Tourism tax applies only to foreigners and the export carries no
    # nationality, so guest_country stays blank and the tax stays off.
    expect(booking.guest_country).to be_blank
    expect(booking.tourism_tax_amount).to be_zero
  end

  it "matches rows it has already imported instead of duplicating them" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    post commit_admin_hotel_reservation_import_path(hotel, latest_import)
    perform_enqueued_jobs
    imported = hotel.bookings.count
    expect(imported).to be_positive

    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    follow_redirect!
    expect(response.body).to include("Already imported")

    post commit_admin_hotel_reservation_import_path(hotel, latest_import)
    expect { perform_enqueued_jobs }.not_to change(Booking, :count)
    expect(hotel.bookings.count).to eq(imported)
  end

  it "resolves the file once, at upload, instead of on every page view" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import

    expect(import.rows.count).to be_positive
    # Viewing the preview must not re-read the spreadsheet.
    expect(Ezee::ReservationListParser).not_to receive(:call)
    get admin_hotel_reservation_import_path(hotel, import)
    expect(response).to have_http_status(:ok)
  end

  it "asks the database once for every reservation already imported" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import
    expect(import.rows.count).to be > 20

    # The lookup used to run per row, which was 1193 queries on the client's
    # real export. It has to stay a single query however long the file is.
    queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 if payload[:sql].to_s.include?("external_reference")
    end
    Ezee::BuildImportRows.call(import: import)
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(queries).to eq(1)
  end

  it "defaults the preview to the rows that need attention" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import
    expect(import.rows.needing_attention.count).to be_positive

    get admin_hotel_reservation_import_path(hotel, import)

    expect(response.body).to include("Needs attention")
    # A blocked row rings the cell that is actually at fault rather than only
    # printing a sentence under the row.
    expect(response.body).to include("ring-red-400")
  end

  it "pages the table lazily instead of rendering every row at once" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import

    get admin_hotel_reservation_import_path(hotel, import, filter: "all")
    # Page one, plus the lazy frame that will fetch page two.
    expect(response.body).to include(%(id="import_rows_page_1"))
    expect(response.body).to include(%(id="import_rows_page_2"))

    get rows_admin_hotel_reservation_import_path(hotel, import, filter: "all", page: 2)

    expect(response).to have_http_status(:ok)
    # Turbo matches a lazy frame's response by id. Without the wrapper it
    # renders "Content missing" at the bottom of the table instead of rows.
    expect(response.body).to include(%(id="import_rows_page_2"))
  end

  it "gives every imported reservation its own guest" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    post commit_admin_hotel_reservation_import_path(hotel, latest_import)
    perform_enqueued_jobs

    bookings = hotel.bookings.where.not(external_reference: nil)
    guest_ids = BookingGuest.where(booking_id: bookings.select(:id)).distinct.pluck(:guest_id)

    # CreateManualBooking matches a guest on phone, and no row in the export has
    # one. A sentinel shared across rows made every reservation resolve to the
    # same guest -- 70 bookings on one guest record.
    expect(guest_ids.size).to eq(bookings.count)
    expect(bookings.pluck(:guest_phone).uniq.size).to eq(bookings.count)
  end

  it "stores the guest name exactly as the export writes it" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    post commit_admin_hotel_reservation_import_path(hotel, latest_import)
    perform_enqueued_jobs

    names = hotel.bookings.where.not(external_reference: nil).pluck(:guest_name)

    # eZee prints "- SOURCE" where the guest name is empty. That is what the
    # file says, so that is what is stored -- the import does not invent a
    # phrase the source does not contain.
    expect(names).to include(a_string_starting_with("-"))
    expect(names).not_to include(a_string_matching(/Name not in export/))
  end

  it "shows the progress page while the import is still running" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import
    post commit_admin_hotel_reservation_import_path(hotel, import)

    get admin_hotel_reservation_import_path(hotel, import)

    expect(response).to have_http_status(:ok)
    # The marker the polling fallback watches: without it a page whose socket
    # never connected would sit at zero forever.
    expect(response.body).to include(%(data-import-running="true"))
    expect(response.body).to include("Waiting to start")
  end

  it "reports a failure on the progress page rather than losing it" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import
    allow(Ezee::ImportReservations).to receive(:call).and_raise(StandardError, "boom")

    post commit_admin_hotel_reservation_import_path(hotel, import)
    perform_enqueued_jobs

    import.reload
    expect(import.status).to eq("failed")
    expect(import.error_message).to eq("boom")

    get admin_hotel_reservation_import_path(hotel, import)
    expect(response.body).to include("The import stopped")
  end

  it "lists past imports for the hotel, newest first" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    older = latest_import
    travel_to(1.hour.from_now) do
      post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    end
    newer = latest_import
    post commit_admin_hotel_reservation_import_path(hotel, newer)
    perform_enqueued_jobs

    get admin_hotel_reservation_imports_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body.index(admin_hotel_reservation_import_path(hotel, newer)))
      .to be < response.body.index(admin_hotel_reservation_import_path(hotel, older))
  end

  it "keeps the full row detail browsable after an import completes, for audit" do
    post admin_hotel_reservation_imports_path(hotel), params: { file: upload }
    import = latest_import
    post commit_admin_hotel_reservation_import_path(hotel, import)
    perform_enqueued_jobs
    import.reload
    expect(import.status).to eq("completed")

    created_row = import.rows.find_by(status: "created")
    expect(created_row.booking_id).to be_present

    get admin_hotel_reservation_import_path(hotel, import)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import completed")
    expect(response.body).to include(created_row.reservation_number)

    # And it stays searchable, same as a draft.
    get admin_hotel_reservation_import_path(hotel, import, q: created_row.reservation_number)
    expect(response.body).to include(created_row.reservation_number)
  end
end
