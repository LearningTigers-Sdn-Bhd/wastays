require "rails_helper"

RSpec.describe HotelPortal::Requests::CompletionWebhook do
  let(:hotel) { create(:hotel, name: "Seaside") }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisyah", confirmation_token: "WS-1", guest_phone: "+60123") }

  def broadcast(request, kind:, from:, to:)
    described_class.broadcast(request: request, kind: kind, from: from, to: to)
  end

  describe "what it announces" do
    it "announces a completed housekeeping request" do
      request = create(:housekeeping_request, booking: booking, status: "completed", completed_at: Time.current)

      expect { broadcast(request, kind: "housekeeping", from: "in_progress", to: "completed") }
        .to have_enqueued_job(WebhookBroadcastJob).with("housekeeping_completed", hash_including(request_id: request.id))
    end

    # Each kind spells finished differently.
    it "announces a resolved complaint, not a completed one" do
      request = create(:complaint_request, booking: booking, status: "resolved", completed_at: Time.current)

      expect { broadcast(request, kind: "complaint", from: "pending", to: "resolved") }
        .to have_enqueued_job(WebhookBroadcastJob).with("complaint_resolved", anything)
    end

    it "announces a completed checkout" do
      request = create(:check_out_request, booking: booking, status: "completed")

      expect { broadcast(request, kind: "checkout", from: "in_progress", to: "completed") }
        .to have_enqueued_job(WebhookBroadcastJob).with("checkout_completed", anything)
    end
  end

  describe "what it keeps quiet about" do
    it "says nothing when the status did not change" do
      request = create(:housekeeping_request, booking: booking, status: "completed", completed_at: Time.current)

      expect { broadcast(request, kind: "housekeeping", from: "completed", to: "completed") }
        .not_to have_enqueued_job(WebhookBroadcastJob)
    end

    it "says nothing about work moving between open statuses" do
      request = create(:housekeeping_request, booking: booking, status: "in_progress")

      expect { broadcast(request, kind: "housekeeping", from: "new", to: "in_progress") }
        .not_to have_enqueued_job(WebhookBroadcastJob)
    end

    # "completed" is housekeeping's ending, not a complaint's.
    it "says nothing about a complaint reaching a status that is not its ending" do
      request = create(:complaint_request, booking: booking, status: "failed")

      expect { broadcast(request, kind: "complaint", from: "pending", to: "completed") }
        .not_to have_enqueued_job(WebhookBroadcastJob)
    end
  end

  describe "what it carries" do
    it "names the guest, the booking and the hotel" do
      request = create(:housekeeping_request, booking: booking, status: "completed",
                       completed_at: Time.current, external_id: "EXT-9")

      broadcast(request, kind: "housekeeping", from: "new", to: "completed")

      expect(WebhookBroadcastJob).to have_been_enqueued.with(
        "housekeeping_completed",
        hash_including(
          external_id: "EXT-9",
          kind: "housekeeping",
          status: "completed",
          booking_id: booking.id,
          confirmation_token: "WS-1",
          guest_name: "Aisyah",
          guest_phone: "+60123",
          hotel_name: "Seaside"
        )
      )
    end

    # A checkout has no external_id column of its own.
    it "reads a checkout's external id out of its metadata" do
      request = create(:check_out_request, booking: booking, status: "completed", metadata: { "external_id" => "EXT-CO" })

      broadcast(request, kind: "checkout", from: "new", to: "completed")

      expect(WebhookBroadcastJob).to have_been_enqueued.with("checkout_completed", hash_including(external_id: "EXT-CO"))
    end
  end
end
