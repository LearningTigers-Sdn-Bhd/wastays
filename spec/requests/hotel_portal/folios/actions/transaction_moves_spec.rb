# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Folios::Actions transaction moves", type: :request, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, status: "open") }
  let(:transaction) do
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
  end
  let(:target_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, label: "Company Folio") }

  before do
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
    grant_permission("view_bookings")
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def folio_operations_path(**params)
    hotel_booking_workspace_path(hotel, booking, { tab: "folio_operations" }.merge(params))
  end

  def move_path(record = transaction, **params)
    hotel_folio_action_move_transaction_path(hotel, booking, record, **params)
  end

  describe "GET the move form" do
    before { grant_permission("manage_folio_movements") }

    it "renders the move Sheet in the primary folio-action frame" do
      target_folio

      get move_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#folio_action_sheet dialog#folio-move-transaction-sheet[data-controller='panels-ui--sheet']")
      expect(dialog).to be_present
      expect(response.body).to include("Move transaction")
      expect(response.body).to include("Company Folio")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders into the secondary frame when launched from a stacked sheet" do
      target_folio

      get move_path, headers: { "Turbo-Frame" => "folio_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet_secondary dialog#folio-move-transaction-sheet")).to be_present
    end

    it "renders a target selector for each attached tax row" do
      room_code = create(:transaction_code, hotel: hotel, code: "ROOM-MOVE", name: "Room Charge", kind: "charge", category: "accommodation")
      tax_code = create(:transaction_code, hotel: hotel, code: "TTX-MOVE", name: "Tourism Tax", kind: "charge", category: "tax")
      parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100, transaction_code: room_code)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 10,
        description: "Tourism Tax", transaction_code: tax_code,
        metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "tourism_tax" } })
      target_folio

      get move_path(parent), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Attached taxes and fees")
      expect(response.body).to include("Follow target folio")
      expect(response.body).to include("TTX-MOVE")

      # The nested names must match what tax_route_params expects.
      tax = folio.folio_transactions.find_by(category: "tax")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("input[name='folio_operation[tax_routes][#{tax.id}][transaction_id]']")).to be_present
      expect(document.at_css("[name='folio_operation[tax_routes][#{tax.id}][target_folio_id]']")).to be_present
    end

    it "renders nightly-style attached taxes linked through the source transaction code" do
      room_code = create(:transaction_code, hotel: hotel, code: "ROOM-NIGHT", name: "Room Charge", kind: "charge", category: "accommodation")
      tax_code = create(:transaction_code, hotel: hotel, code: "TTX-NIGHT", name: "Tourism Tax", kind: "charge", category: "tax")
      parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation",
        amount: 100, posting_date: Date.current, transaction_code: room_code, metadata: { stay_date: Date.current.iso8601 })
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 10,
        description: "Tourism Tax", posting_date: Date.current, transaction_code: tax_code,
        metadata: { stay_date: Date.current.iso8601, tax_line: { type: "tourism_tax", source_transaction_code_id: room_code.id } })
      target_folio

      get move_path(parent), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Attached taxes and fees")
      expect(response.body).to include("TTX-NIGHT")
    end

    it "explains the situation when there is no other open folio to move to" do
      get move_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No other open folio window")
    end

    it "does not find a booking belonging to another hotel" do
      foreign_booking = create(:booking, hotel: other_hotel, status: "checked_in")

      get hotel_folio_action_move_transaction_path(hotel, foreign_booking, transaction),
        headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST the move" do
    before { grant_permission("manage_folio_movements") }

    it "moves the charge and completes the sheet on a Turbo submission" do
      transaction
      target_folio

      expect {
        post move_path,
          params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
      }.to change(FolioTransaction, :count).by(2)
        .and change(FolioOperationLog.where(operation_type: "move_transaction"), :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="folio_action_sheet"')

      moved = target_folio.folio_transactions.charge.order(:id).last
      expect(moved.amount).to eq(100.to_d)
      expect(moved.moved_from_transaction).to eq(transaction)
      expect(transaction.reload.voided_by_transaction).to be_present
      expect(flash[:notice]).to eq("Folio transaction moved.")
    end

    it "completes the frame that launched the sheet" do
      post move_path,
        params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet_secondary" }

      expect(response.body).to include('target="folio_action_sheet_secondary"')
    end

    it "routes attached taxes to explicitly selected folios" do
      tax = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 10,
        description: "Tourism Tax", metadata: { parent_folio_transaction_id: transaction.id, tax_line: { type: "tourism_tax" } })
      tax_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)

      expect {
        post move_path,
          params: {
            folio_operation: {
              target_folio_id: target_folio.id,
              reason: "Route room to company and tax elsewhere",
              tax_routes: { tax.id => { transaction_id: tax.id, target_folio_id: tax_folio.id } }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
      }.to change(FolioTransaction, :count).by(4)

      expect(target_folio.folio_transactions.charge.where(moved_from_transaction: transaction)).to exist
      expect(tax_folio.folio_transactions.charge.where(moved_from_transaction: tax)).to exist
    end

    it "closes the sheet with a flash alert when the move fails" do
      allow(::Folios::Transactions::MoveTransaction).to receive(:call)
        .and_return(double(success?: false, error: "Transaction cannot be moved."))

      post move_path,
        params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to eq("Transaction cannot be moved.")
    end

    it "redirects to the folio tab on a direct request" do
      post move_path, params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } }

      expect(response).to redirect_to(folio_operations_path)
    end
  end

  describe "without manage_folio_movements" do
    it "forbids the form" do
      get move_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "forbids the move before it reaches the service" do
      transaction
      target_folio

      expect(::Folios::Transactions::MoveTransaction).not_to receive(:call)

      expect {
        post move_path, params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } }
      }.not_to change(FolioTransaction, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end
  end

  describe "the return_to destination" do
    before { grant_permission("manage_folio_movements") }

    it "honours a same-origin hotel path" do
      destination = hotel_folio_path(hotel, booking)

      post move_path(transaction, return_to: destination),
        params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } }

      expect(response).to redirect_to(destination)
    end

    it "falls back to the folio tab for an off-origin return_to" do
      post move_path(transaction, return_to: "https://evil.example.com/steal"),
        params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } }

      expect(response).to redirect_to(folio_operations_path)
    end

    it "falls back to the folio tab for a path outside this hotel" do
      post move_path(transaction, return_to: "/admin/hotels"),
        params: { folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" } }

      expect(response).to redirect_to(folio_operations_path)
    end
  end
end
