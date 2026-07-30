require "rails_helper"

RSpec.describe HotelPortal::Requests::Finder do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:other_booking) { create(:booking, hotel: other_hotel) }

  def find(kind:, request_id:, hotel: self.hotel, **options)
    described_class.new(hotel: hotel, kind: kind, request_id: request_id, **options).call
  end

  describe "reaching a request by its hotel" do
    it "finds a housekeeping request that carries its own hotel_id" do
      request = create(:housekeeping_request, booking: booking, hotel: hotel)

      expect(find(kind: "housekeeping", request_id: request.id)).to eq(request)
    end

    # What the concierge page creates: built through the booking, so the
    # request's own hotel_id is never set.
    it "finds a housekeeping request that reaches the hotel only through its booking" do
      request = create(:housekeeping_request, booking: booking, hotel: nil)

      expect(request.hotel_id).to be_nil
      expect(find(kind: "housekeeping", request_id: request.id)).to eq(request)
    end

    it "finds a complaint request through its booking" do
      request = create(:complaint_request, booking: booking)

      expect(find(kind: "complaint", request_id: request.id)).to eq(request)
    end

    it "finds a checkout request through its booking" do
      request = create(:check_out_request, booking: booking)

      expect(find(kind: "checkout", request_id: request.id)).to eq(request)
    end
  end

  describe "refusing another hotel's request" do
    it "refuses a housekeeping request held by another hotel" do
      request = create(:housekeeping_request, booking: other_booking, hotel: other_hotel)

      expect { find(kind: "housekeeping", request_id: request.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "refuses a housekeeping request whose booking belongs to another hotel" do
      request = create(:housekeeping_request, booking: other_booking, hotel: nil)

      expect { find(kind: "housekeeping", request_id: request.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "refuses a complaint request held by another hotel" do
      request = create(:complaint_request, booking: other_booking)

      expect { find(kind: "complaint", request_id: request.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "refuses a checkout request held by another hotel" do
      request = create(:check_out_request, booking: other_booking)

      expect { find(kind: "checkout", request_id: request.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "kinds it will not look up" do
    it "refuses an unknown kind" do
      expect { find(kind: "minibar", request_id: 1) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "refuses a kind the caller did not allow" do
      request = create(:check_out_request, booking: booking)

      expect {
        find(kind: "checkout", request_id: request.id, kinds: %w[housekeeping complaint])
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "raises when the request does not exist" do
    expect { find(kind: "housekeeping", request_id: 0) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
