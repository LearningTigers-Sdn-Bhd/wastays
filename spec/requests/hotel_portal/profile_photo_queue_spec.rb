require "rails_helper"
require "stringio"
require "tempfile"

RSpec.describe "HotelPortal::ProfilePhotoQueue", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_hotel_profile"))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/profile/edit" do
    it "renders the canonical hotel details page" do
      get edit_hotel_profile_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="hotel-profile-section"))
      expect(response.body).to include(%(data-testid="settings-tabs"))
      expect(response.parsed_body.css(".panel-dropzone")).not_to be_empty
      expect(response.parsed_body.css(".panel-attachment-group[data-layout='list']")).not_to be_empty
    end

    it "renders published photos as attachment cards with per-photo actions" do
      hotel.photos.attach(
        io: StringIO.new("published-photo"),
        filename: "published.jpg",
        content_type: "image/jpeg"
      )

      get edit_hotel_profile_path(hotel)

      document = response.parsed_body
      published_attachment = document.at_css(".panel-attachment-group[data-layout='grid'] .panel-attachment[data-state='uploaded']")
      expect(published_attachment.text.squish).to include("published.jpg")
      expect(document.at_css("#hotel-photo-#{hotel.photos.first.id}-actions.dropdown-menu-root")).to be_present
      expect(document.at_css("button[aria-label='Actions for published.jpg']")).to be_present
      expect(document.at_css("button[data-turbo-confirm-tone='destructive']")).to be_present
    end
  end

  describe "DELETE /hotel/:hotel_id/profile/photos/:photo_id" do
    it "removes one published attachment" do
      hotel.photos.attach(
        io: StringIO.new("published-photo"),
        filename: "remove.jpg",
        content_type: "image/jpeg"
      )
      photo = hotel.photos.first

      expect {
        delete hotel_profile_photo_path(hotel, photo.id)
      }.to change { hotel.reload.photos.count }.by(-1)

      expect(response).to redirect_to(edit_hotel_profile_path(hotel))
    end

    it "replaces the published album and appends a toast for Turbo Stream requests" do
      hotel.photos.attach(
        io: StringIO.new("published-photo"),
        filename: "remove-live.jpg",
        content_type: "image/jpeg"
      )
      photo = hotel.photos.first

      delete hotel_profile_photo_path(hotel, photo.id),
             headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace" target="hotel-published-photos"')
      expect(response.body).to include('action="append" target="toast-viewport"')
      expect(response.body).to include("Hotel photo removed successfully.")
      expect(response.body).not_to include("remove-live.jpg")
      expect(hotel.reload.photos).not_to be_attached
    end
  end

  describe "PATCH /hotel/:hotel_id/profile/photos/:photo_id/feature" do
    before do
      %w[first.jpg second.jpg].each do |filename|
        hotel.photos.attach(
          io: StringIO.new("published-photo-#{filename}"),
          filename: filename,
          content_type: "image/jpeg"
        )
      end
    end

    it "replaces the published album and appends a toast for Turbo Stream requests" do
      photo = hotel.photos.attachments.joins(:blob).find_by!(active_storage_blobs: { filename: "second.jpg" })

      patch hotel_profile_photo_feature_path(hotel, photo.id),
            headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace" target="hotel-published-photos"')
      expect(response.body).to include('action="append" target="toast-viewport"')
      expect(response.body).to include("second.jpg", "Featured photo", "Featured photo updated successfully.")
      expect(hotel.reload.featured_photo_attachment_id).to eq(photo.id)
    end

    it "retains the redirect fallback for HTML requests" do
      photo = hotel.photos.attachments.first

      patch hotel_profile_photo_feature_path(hotel, photo.id)

      expect(response).to redirect_to(edit_hotel_profile_path(hotel))
      expect(hotel.reload.featured_photo_attachment_id).to eq(photo.id)
    end
  end

  describe "POST /hotel/:hotel_id/profile/photo_queue" do
    it "queues an image upload" do
      post hotel_profile_photo_queue_path(hotel),
           params: { photo: uploaded_file("queue-photo.jpg", "image/jpeg", "jpeg-content") },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("queue_item", "filename")).to eq("queue-photo.jpg")
      expect(json.dig("summary", "queued_count")).to eq(1)
    end

    it "rejects non-image files" do
      post hotel_profile_photo_queue_path(hotel),
           params: { photo: uploaded_file("note.txt", "text/plain", "hello") },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("Only image files are allowed")
    end
  end

  describe "DELETE /hotel/:hotel_id/profile/photo_queue/:signed_id" do
    it "removes a queued photo" do
      post hotel_profile_photo_queue_path(hotel),
           params: { photo: uploaded_file("remove-me.jpg", "image/jpeg", "jpeg-content") },
           headers: { "ACCEPT" => "application/json" }
      signed_id = JSON.parse(response.body).dig("queue_item", "signed_id")

      delete hotel_profile_photo_queue_item_path(hotel, signed_id), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("summary", "queued_count")).to eq(0)
    end
  end

  describe "DELETE /hotel/:hotel_id/profile/photo_queue" do
    it "clears all queued photos" do
      2.times do |index|
        post hotel_profile_photo_queue_path(hotel),
             params: { photo: uploaded_file("clear-#{index}.jpg", "image/jpeg", "jpeg-content") },
             headers: { "ACCEPT" => "application/json" }
      end

      delete hotel_clear_profile_photo_queue_path(hotel), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("summary", "queued_count")).to eq(0)
    end
  end

  describe "POST /hotel/:hotel_id/profile/photo_queue/commit" do
    it "attaches queued photos and clears the queue" do
      2.times do |index|
        post hotel_profile_photo_queue_path(hotel),
             params: { photo: uploaded_file("commit-#{index}.jpg", "image/jpeg", "jpeg-content") },
             headers: { "ACCEPT" => "application/json" }
      end

      post hotel_commit_profile_photo_queue_path(hotel), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["attached_count"]).to eq(2)
      expect(json.dig("summary", "queued_count")).to eq(0)
      expect(hotel.reload.photos.count).to eq(2)
    end

    it "prevents queueing when max photos is already reached" do
      Hotel::MAX_PHOTOS.times do |index|
        hotel.photos.attach(
          io: StringIO.new("existing-photo"),
          filename: "existing-#{index}.jpg",
          content_type: "image/jpeg"
        )
      end

      post hotel_profile_photo_queue_path(hotel),
           params: { photo: uploaded_file("overflow.jpg", "image/jpeg", "jpeg-content") },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("maximum of 20 photos")
    end
  end

  def uploaded_file(filename, content_type, content)
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end
end
