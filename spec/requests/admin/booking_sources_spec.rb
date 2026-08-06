# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::BookingSources", type: :request do
  let(:admin_account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }
  let(:logo) { fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg") }

  before { sign_in_as(superadmin) }

  describe "GET /admin/booking_sources" do
    it "renders the index with seeded sources" do
      get admin_booking_sources_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Booking.com")
    end
  end

  describe "GET /admin/booking_sources/new" do
    it "renders the form with the icon reference datalist" do
      get new_admin_booking_source_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lucide-icon-names")
    end

    it "shows the fallback badge section by default, since new sources default to the OTA category" do
      get new_admin_booking_source_path
      section = Nokogiri::HTML(response.body).at_css('[data-booking-source-preview-target="otaOnlySection"]')

      expect(section["class"]).not_to include("hidden")
    end

    it "renders the category field as a styled SelectMenu and the logo field as a Dropzone" do
      get new_admin_booking_source_path
      doc = Nokogiri::HTML(response.body)

      select_menu = doc.at_css(".panel-select-menu")
      expect(select_menu).to be_present
      expect(select_menu.at_css('select[name="booking_source[kind]"]')).to be_present

      dropzone = doc.at_css(".panel-dropzone")
      expect(dropzone).to be_present
      expect(dropzone.at_css('input[type="file"][name="booking_source[logo]"]')).to be_present
    end
  end

  describe "GET /admin/booking_sources/:id/edit" do
    it "renders the form for an existing source, including a remove-logo option when a logo is attached" do
      source = create(:booking_source, key: "editable_with_logo")
      source.logo.attach(io: Rails.root.join("spec/fixtures/files/sample_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")

      get edit_admin_booking_source_path(source)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Remove current logo")
    end

    it "hides the fallback badge section server-side for a Manual/Direct source" do
      source = create(:booking_source, key: "manual_edit_test", kind: "manual")

      get edit_admin_booking_source_path(source)
      section = Nokogiri::HTML(response.body).at_css('[data-booking-source-preview-target="otaOnlySection"]')

      expect(section["class"]).to include("hidden")
    end
  end

  describe "GET /admin/booking_sources/icon_preview" do
    it "renders the requested icon when it's a real Lucide icon name" do
      get icon_preview_admin_booking_sources_path(name: "credit-card")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("svg")
    end

    it "renders a placeholder for an unrecognized icon name" do
      get icon_preview_admin_booking_sources_path(name: "not-a-real-icon")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("text-muted-foreground/50")
    end
  end

  describe "POST /admin/booking_sources" do
    let(:valid_params) do
      {
        booking_source: {
          key: "tiktok_shop", label: "TikTok Shop", kind: "ota",
          badge_color: "#010101", badge_text_color: "#FFFFFF", badge_initial: "T", logo: logo
        }
      }
    end

    it "creates a new booking source with an attached logo" do
      expect {
        post admin_booking_sources_path, params: valid_params
      }.to change(BookingSource, :count).by(1)

      expect(response).to redirect_to(admin_booking_sources_path)
      source = BookingSource.find_by(key: "tiktok_shop")
      expect(source.logo).to be_attached
      expect(HotelPortal::BookingSourcePresenter.ota_options.map(&:last)).to include("tiktok_shop")
    end

    it "re-renders the form with errors for an invalid source" do
      post admin_booking_sources_path, params: { booking_source: { key: "", label: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(BookingSource.exists?(key: "")).to be(false)
    end

    it "auto-assigns the next position within the same kind, appending to the end" do
      max_position = BookingSource.where(kind: "ota").maximum(:position).to_i

      post admin_booking_sources_path, params: valid_params

      expect(BookingSource.find_by(key: "tiktok_shop").position).to eq(max_position + 1)
    end
  end

  describe "PATCH /admin/booking_sources/:id" do
    it "updates the source and it takes effect immediately in the shared registry" do
      source = create(:booking_source, key: "editable_source", label: "Old Label")

      patch admin_booking_source_path(source), params: { booking_source: { label: "New Label" } }

      expect(response).to redirect_to(admin_booking_sources_path)
      expect(source.reload.label).to eq("New Label")
      expect(HotelPortal::BookingSourcePresenter.new("editable_source").label).to eq("New Label")
    end

    it "removes the logo when the remove_logo flag is set without a replacement upload" do
      source = create(:booking_source, key: "with_logo")
      source.logo.attach(io: Rails.root.join("spec/fixtures/files/sample_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")

      patch admin_booking_source_path(source), params: { booking_source: { label: source.label, remove_logo: "1" } }

      expect(response).to redirect_to(admin_booking_sources_path)
      expect(source.reload.logo).not_to be_attached
    end

    it "keeps a newly uploaded logo even if remove_logo is also set" do
      source = create(:booking_source, key: "with_logo_replaced")
      source.logo.attach(io: Rails.root.join("spec/fixtures/files/sample_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")

      patch admin_booking_source_path(source), params: { booking_source: { label: source.label, remove_logo: "1", logo: logo } }

      expect(source.reload.logo).to be_attached
    end

    it "busts the cached registry when the logo is removed, even with a real cache backend and no other field changes" do
      with_real_cache_store do
        source = create(:booking_source, key: "cache_test_logo")
        source.logo.attach(io: Rails.root.join("spec/fixtures/files/sample_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")
        expect(HotelPortal::BookingSourcePresenter.new("cache_test_logo").logo).to be_attached # warms the cache

        patch admin_booking_source_path(source), params: { booking_source: { label: source.label, remove_logo: "1" } }

        expect(HotelPortal::BookingSourcePresenter.new("cache_test_logo").logo).to be_nil
      end
    end
  end

  describe "PATCH /admin/booking_sources/reorder" do
    it "persists the new order within a kind and busts the shared registry cache" do
      first = create(:booking_source, key: "reorder_a", kind: "ota", position: 0)
      second = create(:booking_source, key: "reorder_b", kind: "ota", position: 1)

      patch reorder_admin_booking_sources_path, params: { kind: "ota", ordered_ids: [ second.id, first.id ] }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(second.reload.position).to eq(0)
      expect(first.reload.position).to eq(1)
      expect(BookingSource.ota_options.map(&:last).index("reorder_b")).to be < BookingSource.ota_options.map(&:last).index("reorder_a")
    end

    it "does not move rows belonging to a different kind" do
      manual_source = create(:booking_source, key: "reorder_manual", kind: "manual", position: 0)

      patch reorder_admin_booking_sources_path, params: { kind: "ota", ordered_ids: [ manual_source.id ] }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(manual_source.reload.position).to eq(0)
    end
  end

  describe "PATCH /admin/booking_sources/:id/toggle" do
    it "deactivates and reactivates a source without deleting it" do
      source = create(:booking_source, active: true)

      patch toggle_admin_booking_source_path(source)
      expect(source.reload.active).to be(false)

      patch toggle_admin_booking_source_path(source)
      expect(source.reload.active).to be(true)
    end

    it "keeps the source resolvable for historical bookings while deactivated" do
      source = create(:booking_source, key: "old_channel", label: "Old Channel", active: true)
      patch toggle_admin_booking_source_path(source)

      expect(HotelPortal::BookingSourcePresenter.new("old_channel").label).to eq("Old Channel")
      expect(BookingSource.ota_options.map(&:last)).not_to include("old_channel")
    end
  end
end
