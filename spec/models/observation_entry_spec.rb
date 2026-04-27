require 'rails_helper'

RSpec.describe ObservationEntry, type: :model do
  describe "#human_title" do
    it "returns 'Guest login link requested' for guest magic link request" do
      entry = ObservationEntry.new(entry_type: "request", path: "POST /guest/request_magic_link")
      expect(entry.human_title).to eq("Guest login link requested")
    end

    it "returns 'Guest viewed login page' for guest login view" do
      entry = ObservationEntry.new(entry_type: "request", path: "GET /guest/login")
      expect(entry.human_title).to eq("Guest viewed login page")
    end

    it "returns 'New booking attempt' for new booking request" do
      entry = ObservationEntry.new(entry_type: "request", path: "POST /api/v1/bookings")
      expect(entry.human_title).to eq("New booking attempt")
    end

    it "returns 'Admin viewed observation deck' for observation deck view" do
      entry = ObservationEntry.new(entry_type: "request", path: "GET /admin/observation_deck")
      expect(entry.human_title).to eq("Admin viewed observation deck")
    end

    it "returns 'Web Request: path' for other requests" do
      entry = ObservationEntry.new(entry_type: "request", path: "GET /some/other/path")
      expect(entry.human_title).to eq("Web Request: /some/other/path")
    end

    it "returns 'Background Task: path' for job entry type" do
      entry = ObservationEntry.new(entry_type: "job", path: "SomeJob (Enqueued)")
      expect(entry.human_title).to eq("Background Task: SomeJob")
    end

    it "returns 'Email Sent: path' for mail entry type" do
      entry = ObservationEntry.new(entry_type: "mail", path: "UserMailer#welcome")
      expect(entry.human_title).to eq("Email Sent: UserMailer#welcome")
    end

    it "returns 'Database: path' for sql entry type" do
      entry = ObservationEntry.new(entry_type: "sql", path: "SELECT * FROM users")
      expect(entry.human_title).to eq("Database: SELECT * FROM users")
    end

    it "returns 'Channel Manager Update (Channex)' for api entry type containing channex" do
      entry = ObservationEntry.new(entry_type: "api", path: "POST /channex/update")
      expect(entry.human_title).to eq("Channel Manager Update (Channex)")
    end

    it "returns 'Payment Gateway Action (Razorpay)' for api entry type containing razorpay" do
      entry = ObservationEntry.new(entry_type: "api", path: "POST /razorpay/charge")
      expect(entry.human_title).to eq("Payment Gateway Action (Razorpay)")
    end

    it "returns 'External API Call' for other api entry types" do
      entry = ObservationEntry.new(entry_type: "api", path: "POST /external/api")
      expect(entry.human_title).to eq("External API Call")
    end

    it "returns titleized entry_type for other types" do
      entry = ObservationEntry.new(entry_type: "custom_event")
      expect(entry.human_title).to eq("Custom Event")
    end
  end

  describe "#human_identity" do
    it "returns Admin name if user tag is present" do
      user = create(:user, name: "Test Admin")
      entry = ObservationEntry.new(tags: ["user:#{user.id}"])
      expect(entry.human_identity).to eq("Admin: Test Admin")
    end

    it "returns Booking ID if booking tag is present" do
      entry = ObservationEntry.new(tags: ["booking:12345"])
      expect(entry.human_identity).to eq("Booking #12345")
    end

    it "returns 'System / Guest' if neither user nor booking tags are present" do
      entry = ObservationEntry.new(tags: ["other:tag"])
      expect(entry.human_identity).to eq("System / Guest")
    end

    it "returns 'System / Guest' if no tags are present" do
      entry = ObservationEntry.new(tags: [])
      expect(entry.human_identity).to eq("System / Guest")
    end
  end
end
