# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Reports::NightAudits", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    grant_permission("view_reports")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "lists reportable audits in recent-first order and excludes preparing records" do
    older = create(:night_audit, hotel: hotel, business_date: Date.new(2026, 7, 30), status: "completed")
    newer = create(:night_audit, hotel: hotel, business_date: Date.new(2026, 7, 31), status: "failed")
    preparing = create(:night_audit, hotel: hotel, business_date: Date.new(2026, 8, 1), status: "preparing")

    get hotel_reports_night_audits_path(hotel)

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    rows = page.all("tbody tr").map(&:text)
    expect(rows.join(" ")).to include(newer.business_date.strftime("%d %b %Y"), older.business_date.strftime("%d %b %Y"))
    expect(rows.join(" ")).not_to include(preparing.business_date.strftime("%d %b %Y"))
    expect(rows.first).to include(newer.business_date.strftime("%d %b %Y"))
  end

  it "allows manage-night-audit staff to read the index, detail, and PDF without view-reports permission" do
    role.permissions.clear
    grant_permission("manage_night_audit")
    audit = create(:night_audit, hotel: hotel, status: "completed")
    exporter = instance_double(NightAudits::AuditPacketPdfExport, generate: "%PDF-report")
    allow(NightAudits::AuditPacketPdfExport).to receive(:new).with(
      night_audit: audit, prepared_by: user.name
    ).and_return(exporter)

    get hotel_reports_night_audits_path(hotel)
    expect(response).to have_http_status(:ok)

    get hotel_reports_night_audit_path(hotel, audit)
    expect(response).to have_http_status(:ok)

    get hotel_reports_night_audit_path(hotel, audit, format: :pdf)
    expect(response).to have_http_status(:ok)
  end

  it "rejects index, detail, and PDF access without either report permission" do
    role.permissions.clear
    audit = create(:night_audit, hotel: hotel, status: "completed")

    [
      hotel_reports_night_audits_path(hotel),
      hotel_reports_night_audit_path(hotel, audit),
      hotel_reports_night_audit_path(hotel, audit, format: :pdf)
    ].each do |path|
      get path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
    end
  end

  it "shows only a reportable audit belonging to the current hotel" do
    audit = create(:night_audit, hotel: hotel, business_date: Date.new(2026, 7, 31), status: "completed")
    create(:night_audit_financial_summary, night_audit: audit, room_revenue: 320, tax_revenue: 25)

    get hotel_reports_night_audit_path(hotel, audit)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Night audit report", "31 Jul 2026", "Financial summary")
    page = Capybara.string(response.body)
    expect(page).to have_css(".tabs-root--line")
    expect(page).to have_css("[data-slot='tabs-trigger']", text: "Results")
    expect(page).to have_css("[data-slot='tabs-trigger']", text: "Financial summary")
    expect(page).to have_css("[data-slot='tabs-trigger']", text: "Adjustments")
    expect(page).to have_css("table caption", text: "Night audit blockers", visible: :all)
    expect(page).to have_css("table caption", text: "Night audit warnings", visible: :all)
  end

  it "returns not found for a preparing audit" do
    audit = create(:night_audit, hotel: hotel, status: "preparing")

    get hotel_reports_night_audit_path(hotel, audit)

    expect(response).to have_http_status(:not_found)
  end

  it "returns not found for an audit belonging to another hotel" do
    audit = create(:night_audit, hotel: create(:hotel), status: "completed")

    get hotel_reports_night_audit_path(hotel, audit)

    expect(response).to have_http_status(:not_found)
  end

  it "exports the existing audit packet for an authorized reader" do
    audit = create(:night_audit, hotel: hotel, status: "completed")
    exporter = instance_double(NightAudits::AuditPacketPdfExport, generate: "%PDF-report")
    allow(NightAudits::AuditPacketPdfExport).to receive(:new).with(
      night_audit: audit, prepared_by: user.name
    ).and_return(exporter)

    get hotel_reports_night_audit_path(hotel, audit, format: :pdf)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to eq("%PDF-report")
    expect(response.headers["Content-Disposition"]).to include("inline", "Audit_Packet_")
  end

  private

  def grant_permission(slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.titleize)
    role.permissions << permission unless role.permissions.include?(permission)
  end
end
